package com.junwan666.openclawzh

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.os.Build
import android.system.Os
import io.flutter.FlutterInjector
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.FileNotFoundException
import java.io.InputStream
import java.io.OutputStream
import java.util.zip.GZIPInputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream
import org.json.JSONArray
import org.json.JSONObject
import org.apache.commons.compress.archivers.ar.ArArchiveInputStream
import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.xz.XZCompressorInputStream
import org.apache.commons.compress.compressors.zstandard.ZstdCompressorInputStream

class BootstrapManager(
    private val context: Context,
    private val filesDir: String,
    private val nativeLibDir: String
) {
    private val rootfsDir get() = "$filesDir/rootfs/ubuntu"
    private val rootfsStagingDir get() = "$filesDir/rootfs-staging/ubuntu"
    private val rootfsRollbackDir get() = "$filesDir/rootfs-rollback/ubuntu"
    private val runtimeStateDir get() = "$filesDir/runtime"
    private val installationLock get() = File(runtimeStateDir, "installation.lock")
    private val tmpDir get() = "$filesDir/tmp"
    private val homeDir get() = "$filesDir/home"
    private val configDir get() = "$filesDir/config"
    private val libDir get() = "$filesDir/lib"
    private val nativeRuntimeDir get() = "$filesDir/native"
    private val workspaceRootDir get() = File("$rootfsDir/root/.openclaw")
    private val workspaceBackupManifestName = "openclaw-workspace-backup.json"
    private val workspaceBackupFormat = "openclaw-workspace-backup"
    private val workspaceBackupRelativePaths = listOf(
        ".env",
        "openclaw.json",
        "data",
        "memory",
        "skills",
        "config",
        "extensions",
        "agents",
        // 2026.7.x 将 Goals、共享状态和配对信息迁移到以下目录。
        "state",
        "devices",
        "nodes",
        "identity",
        "workspace",
        "canvas",
        "skill-workshop",
    )

    fun setupDirectories() {
        listOf(
            rootfsDir to "Ubuntu rootfs directory",
            tmpDir to "temporary directory",
            homeDir to "home directory",
            configDir to "config directory",
            "$homeDir/.openclaw" to "OpenClaw home directory",
            libDir to "library directory",
            nativeRuntimeDir to "native runtime directory",
        ).forEach { (path, label) ->
            HostFilesystem.ensureDirectoryReady(path, label)
        }
        setupNativeRuntimeBinaries()
        // Termux's proot links against libtalloc.so.2 but Android extracts it
        // as libtalloc.so (jniLibs naming convention). Create a copy with the
        // correct SONAME so the dynamic linker finds it.
        setupLibtalloc()
        ensureRootfsRuntimeDirectories()
        // Create fake /proc and /sys files for proot bind mounts
        setupFakeSysdata()
        ensureDefaultTimezone()
    }

    private fun ensureRootfsRuntimeDirectories() {
        listOf(
            "$rootfsDir/var/cache/apt",
            "$rootfsDir/var/cache/apt/archives",
            "$rootfsDir/var/cache/apt/archives/partial",
            "$rootfsDir/var/lib/apt",
            "$rootfsDir/var/lib/apt/lists",
            "$rootfsDir/var/lib/apt/lists/partial",
            "$rootfsDir/var/log/apt",
            "$rootfsDir/var/lib/dpkg/updates",
            "$rootfsDir/var/lib/dpkg/triggers",
            "$rootfsDir/tmp",
            "$rootfsDir/var/tmp",
            "$rootfsDir/run",
            "$rootfsDir/run/lock",
            "$rootfsDir/dev/shm",
        ).forEach { path ->
            HostFilesystem.ensureDirectoryReady(path, "rootfs runtime directory")
        }
    }

    private fun setupNativeRuntimeBinaries() {
        listOf(
            "libproot.so",
            "libprootloader.so",
            "libprootloader32.so",
            "libtalloc.so",
            "libandroid-shmem.so",
        ).forEach { libName ->
            ensureNativeRuntimeBinary(libName)
        }
    }

    private fun ensureNativeRuntimeBinary(libName: String) {
        val target = File("$nativeRuntimeDir/$libName")
        if (target.exists() && target.length() > 0L) {
            target.setReadable(true, false)
            target.setExecutable(true, false)
            return
        }

        val directSource = File("$nativeLibDir/$libName")
        if (directSource.exists() && directSource.length() > 0L) {
            directSource.copyTo(target, overwrite = true)
            target.setReadable(true, false)
            target.setExecutable(true, false)
            return
        }

        extractNativeLibraryFromApk(libName, target)
    }

    private fun extractNativeLibraryFromApk(libName: String, target: File) {
        val apkPath = context.applicationInfo.sourceDir ?: return
        val abiDirs = resolveApkAbiDirs()

        ZipFile(apkPath).use { zip ->
            for (abiDir in abiDirs) {
                val entry = zip.getEntry("lib/$abiDir/$libName") ?: continue
                target.parentFile?.mkdirs()
                zip.getInputStream(entry).use { input ->
                    FileOutputStream(target).use { output ->
                        input.copyTo(output)
                    }
                }
                target.setReadable(true, false)
                target.setExecutable(true, false)
                return
            }
        }
    }

    private fun resolveApkAbiDirs(): List<String> {
        val supported = Build.SUPPORTED_ABIS?.mapNotNull { abi ->
            when (abi.lowercase()) {
                "arm64-v8a" -> "arm64-v8a"
                "armeabi-v7a", "armeabi" -> "armeabi-v7a"
                "x86_64" -> "x86_64"
                "x86" -> "x86"
                else -> null
            }
        } ?: emptyList()

        return (supported + listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86"))
            .distinct()
    }

    private fun setupLibtalloc() {
        val runtimeSource = File("$nativeRuntimeDir/libtalloc.so")
        val source = if (runtimeSource.exists() && runtimeSource.length() > 0L) {
            runtimeSource
        } else {
            File("$nativeLibDir/libtalloc.so")
        }
        val target = File("$libDir/libtalloc.so.2")
        if (source.exists() && (!target.exists() || target.length() != source.length())) {
            source.copyTo(target, overwrite = true)
            target.setExecutable(true)
            target.setReadable(true, false)
        }
    }

    fun isBootstrapComplete(): Boolean {
        val rootfs = File(rootfsDir)
        val binBash = File("$rootfsDir/bin/bash")
        val bypass = File("$rootfsDir/root/.openclaw/bionic-bypass.js")
        val node = File("$rootfsDir/usr/local/bin/node")
        val openclaw = File("$rootfsDir/usr/local/lib/node_modules/openclaw/package.json")
        val openclawCommand = File("$rootfsDir/usr/local/bin/openclaw")
        return rootfs.exists() && binBash.exists() && bypass.exists()
            && node.exists() && openclaw.exists() && openclawCommand.exists()
    }

    fun getBootstrapStatus(): Map<String, Any> {
        val rootfsExists = File(rootfsDir).exists()
        // setupDirectories() intentionally creates a small runtime skeleton under
        // the RootFS path before the first installation. Do not treat that
        // application-owned skeleton as evidence that RootFS extraction started.
        val rootfsPayloadExists = listOf("bin", "usr", "lib", "sbin", "root")
            .any { File(rootfsDir, it).exists() }
        val binBashExists = File("$rootfsDir/bin/bash").exists()
        val nodeExists = File("$rootfsDir/usr/local/bin/node").exists()
        val openclawPackageExists = File("$rootfsDir/usr/local/lib/node_modules/openclaw/package.json").exists()
        val openclawCommandExists = File("$rootfsDir/usr/local/bin/openclaw").exists()
        val openclawExists = openclawPackageExists && openclawCommandExists
        val bypassExists = File("$rootfsDir/root/.openclaw/bionic-bypass.js").exists()
        val nodeWrapperExists = File("$rootfsDir/root/.openclaw/node-wrapper.js").exists()
        val prootCompatExists = File("$rootfsDir/root/.openclaw/proot-compat.js").exists()
        val openclawCommandFile = File("$rootfsDir/usr/local/bin/openclaw")
        val openclawCommandIsSymlink = try {
            java.nio.file.Files.isSymbolicLink(openclawCommandFile.toPath())
        } catch (_: Exception) {
            false
        }
        val workspace = File("$rootfsDir/root/.openclaw")
        val configExists = File(workspace, "openclaw.json").exists()
        val envExists = File(workspace, ".env").exists()
        val agentsExist = File(workspace, "agents").exists()
        val dataExists = File(workspace, "data").exists()
        val memoryExists = File(workspace, "memory").exists()
        val userDataExists = configExists || envExists || agentsExist ||
            dataExists || memoryExists
        val nodeModulesDir = File("$rootfsDir/usr/local/lib/node_modules")
        val partialOpenClawPackageExists = nodeModulesDir.listFiles()?.any {
            it.name.startsWith(".openclaw-") || it.name.startsWith("openclaw.tmp")
        } == true
        val npmResidueExists = partialOpenClawPackageExists || listOf(
            File("$rootfsDir/root/.npm/_cacache/tmp"),
            File("$rootfsDir/tmp/npm-cache/_cacache/tmp"),
        ).any { candidate ->
            candidate.exists() && (candidate.isFile || !candidate.listFiles().isNullOrEmpty())
        }
        val basePackageBinaries = listOf(
            "$rootfsDir/usr/bin/git",
            "$rootfsDir/usr/bin/python3",
            "$rootfsDir/usr/bin/make",
            "$rootfsDir/usr/bin/g++",
            "$rootfsDir/usr/bin/curl",
            "$rootfsDir/usr/bin/wget",
        )
        val caCertificatesReady =
            File("$rootfsDir/etc/ssl/certs/ca-certificates.crt").exists() ||
            File("$rootfsDir/usr/sbin/update-ca-certificates").exists()
        val basePackagesInstalled = binBashExists &&
            basePackageBinaries.all { File(it).exists() } &&
            caCertificatesReady
        val pendingUpgradeTransactionId = findPendingUpgradeTransactionId() ?: ""

        return mapOf(
            "rootfsExists" to rootfsExists,
            "rootfsPayloadExists" to rootfsPayloadExists,
            "binBashExists" to binBashExists,
            "nodeInstalled" to nodeExists,
            "openclawInstalled" to openclawExists,
            "openclawPackageExists" to openclawPackageExists,
            "openclawCommandExists" to openclawCommandExists,
            "openclawCommandIsSymlink" to openclawCommandIsSymlink,
            "bypassInstalled" to bypassExists,
            "nodeWrapperInstalled" to nodeWrapperExists,
            "prootCompatInstalled" to prootCompatExists,
            "configExists" to configExists,
            "envExists" to envExists,
            "agentsExist" to agentsExist,
            "dataExists" to dataExists,
            "memoryExists" to memoryExists,
            "userDataExists" to userDataExists,
            "npmResidueExists" to npmResidueExists,
            "pendingUpgradeTransactionId" to pendingUpgradeTransactionId,
            "basePackagesInstalled" to basePackagesInstalled,
            "rootfsPath" to rootfsDir,
            "complete" to (rootfsExists && binBashExists && bypassExists
                && nodeExists && openclawExists)
        )
    }

    @Synchronized
    fun extractRootfs(tarPath: String) {
        recoverInterruptedRootfsInstall()
        val staging = File(rootfsStagingDir)
        val hadCurrentRootfs = File(rootfsDir).exists()
        if (staging.exists()) deleteRecursively(staging)
        staging.mkdirs()
        File(runtimeStateDir).mkdirs()
        writeInstallationLock("extracting", hadCurrentRootfs)

        try {
            extractRootfsArchive(tarPath, staging)
            preserveExistingWorkspace(staging)
            writeInstallationLock("activating", hadCurrentRootfs)
            switchStagingRootfs(staging)
            writeInstallationLock("verifying", hadCurrentRootfs)
            configureRootfs()
            ensureRootfsRuntimeDirectories()
        } catch (error: Exception) {
            try {
                rollbackRootfsInstall()
            } catch (rollbackError: Exception) {
                throw RuntimeException(
                    "Rootfs extraction failed: ${error.message}; " +
                        "rollback also failed: ${rollbackError.message}",
                    rollbackError,
                )
            }
            throw error
        } finally {
            File(tarPath).delete()
        }
    }

    private fun writeInstallationLock(phase: String, hadCurrentRootfs: Boolean) {
        installationLock.writeText(
            JSONObject()
                .put("schemaVersion", 1)
                .put("phase", phase)
                .put("hadCurrentRootfs", hadCurrentRootfs)
                .put("startedAt", System.currentTimeMillis())
                .toString()
        )
    }

    private fun extractRootfsArchive(tarPath: String, rootfs: File) {
        val rootfsPath = rootfs.canonicalPath

        // Pure Java extraction using Apache Commons Compress.
        // Two-phase approach:
        //   Phase 1: Extract directories, regular files, and hard links (as copies).
        //   Phase 2: Create all symlinks (deferred so directory structure exists first).
        // This handles tarball entry ordering issues (e.g., bin/bash before bin鈫抲sr/bin).
        val deferredSymlinks = mutableListOf<Pair<String, String>>() // target, path
        var entryCount = 0
        var fileCount = 0
        var symlinkCount = 0
        var extractionError: Exception? = null

        try {
            FileInputStream(tarPath).use { fis ->
                BufferedInputStream(fis, 256 * 1024).use { bis ->
                    GZIPInputStream(bis).use { gis ->
                        TarArchiveInputStream(gis).use { tis ->
                            var entry: TarArchiveEntry? = tis.nextEntry
                            while (entry != null) {
                                entryCount++
                                val name = entry.name
                                    .removePrefix("./")
                                    .removePrefix("/")

                                if (name.isEmpty() || name.startsWith("dev/") || name == "dev") {
                                    entry = tis.nextEntry
                                    continue
                                }

                                val outFile = File(rootfs, name)
                                val outPath = outFile.canonicalPath
                                if (outPath != rootfsPath &&
                                    !outPath.startsWith("$rootfsPath${File.separator}")) {
                                    throw RuntimeException("Unsafe archive path: ${entry.name}")
                                }

                                when {
                                    entry.isDirectory -> {
                                        outFile.mkdirs()
                                    }
                                    entry.isSymbolicLink -> {
                                        // Defer symlinks to phase 2
                                        deferredSymlinks.add(
                                            Pair(entry.linkName, outFile.absolutePath)
                                        )
                                        symlinkCount++
                                    }
                                    entry.isLink -> {
                                        // Hard link 鈫?copy the target file
                                        val target = entry.linkName
                                            .removePrefix("./")
                                            .removePrefix("/")
                                        val targetFile = File(rootfs, target)
                                        outFile.parentFile?.mkdirs()
                                        try {
                                            if (targetFile.exists()) {
                                                targetFile.copyTo(outFile, overwrite = true)
                                                if (targetFile.canExecute()) {
                                                    outFile.setExecutable(true, false)
                                                }
                                                fileCount++
                                            }
                                        } catch (_: Exception) {}
                                    }
                                    else -> {
                                        // Regular file
                                        outFile.parentFile?.mkdirs()
                                        FileOutputStream(outFile).use { fos ->
                                            val buf = ByteArray(65536)
                                            var len: Int
                                            while (tis.read(buf).also { len = it } != -1) {
                                                fos.write(buf, 0, len)
                                            }
                                        }
                                        outFile.setReadable(true, false)
                                        outFile.setWritable(true, false)
                                        val mode = entry.mode
                                        if (mode == 0 || mode and 0b001_001_001 != 0) {
                                            val path = name.lowercase()
                                            if (mode and 0b001_001_001 != 0 ||
                                                path.contains("/bin/") ||
                                                path.contains("/sbin/") ||
                                                path.endsWith(".sh") ||
                                                path.contains("/lib/apt/methods/")) {
                                                outFile.setExecutable(true, false)
                                            }
                                        }
                                        fileCount++
                                    }
                                }

                                entry = tis.nextEntry
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            extractionError = e
        }

        if (entryCount == 0) {
            throw RuntimeException(
                "Extraction failed: tarball appears empty or corrupt. " +
                "Error: ${extractionError?.message ?: "none"}"
            )
        }

        if (extractionError != null) {
            throw RuntimeException(
                "Extraction failed after $entryCount entries ($fileCount files): " +
                "${extractionError!!.message}"
            )
        }

        // Phase 2: Create all symlinks now that the directory structure exists.
        var symlinkErrors = 0
        var lastSymlinkError = ""
        for ((target, path) in deferredSymlinks) {
            try {
                val file = File(path)
                if (file.exists()) {
                    if (file.isDirectory) {
                        val linkTarget = if (target.startsWith("/")) {
                            target.removePrefix("/")
                        } else {
                            val parent = file.parentFile?.absolutePath ?: rootfs.absolutePath
                            File(parent, target).relativeTo(rootfs).path
                        }
                        val realTargetDir = File(rootfs, linkTarget)
                        if (realTargetDir.exists() && realTargetDir.isDirectory) {
                            file.listFiles()?.forEach { child ->
                                val dest = File(realTargetDir, child.name)
                                if (!dest.exists()) {
                                    child.renameTo(dest)
                                }
                            }
                        }
                        deleteRecursively(file)
                    } else {
                        file.delete()
                    }
                }
                file.parentFile?.mkdirs()
                Os.symlink(target, path)
            } catch (e: Exception) {
                symlinkErrors++
                lastSymlinkError = "$path -> $target: ${e.message}"
            }
        }

        // Verify extraction
        if (!File(rootfs, "bin/bash").exists() &&
            !File(rootfs, "usr/bin/bash").exists()) {
            throw RuntimeException(
                "Extraction failed: bash not found in rootfs. " +
                "Processed $entryCount entries, $fileCount files, " +
                "$symlinkCount symlinks (${symlinkErrors} symlink errors). " +
                "Last symlink error: $lastSymlinkError. " +
                "usr/bin exists: ${File(rootfs, "usr/bin").exists()}. " +
                "Extraction error: ${extractionError?.message ?: "none"}"
            )
        }

    }

    private fun preserveExistingWorkspace(staging: File) {
        val source = workspaceRootDir
        if (!source.exists()) return
        val destination = File(staging, "root/.openclaw")
        destination.mkdirs()
        workspaceBackupRelativePaths.forEach { relativePath ->
            val sourceEntry = File(source, relativePath)
            if (!sourceEntry.exists()) return@forEach
            val destinationEntry = File(destination, relativePath)
            if (sourceEntry.isDirectory) {
                sourceEntry.copyRecursively(destinationEntry, overwrite = true)
            } else {
                destinationEntry.parentFile?.mkdirs()
                sourceEntry.copyTo(destinationEntry, overwrite = true)
            }
        }
    }

    private fun switchStagingRootfs(staging: File) {
        val current = File(rootfsDir)
        val rollback = File(rootfsRollbackDir)
        if (rollback.exists()) deleteRecursively(rollback)
        rollback.parentFile?.mkdirs()
        if (current.exists() && !current.renameTo(rollback)) {
            throw RuntimeException("Unable to move current rootfs to rollback directory")
        }
        current.parentFile?.mkdirs()
        if (!staging.renameTo(current)) {
            if (rollback.exists()) rollback.renameTo(current)
            throw RuntimeException("Unable to activate staged rootfs")
        }
    }

    @Synchronized
    fun commitRootfsInstall() {
        val rollback = File(rootfsRollbackDir)
        if (rollback.exists()) deleteRecursively(rollback)
        val staging = File(rootfsStagingDir)
        if (staging.exists()) deleteRecursively(staging)
        installationLock.delete()
    }

    @Synchronized
    fun rollbackRootfsInstall() {
        val current = File(rootfsDir)
        val rollback = File(rootfsRollbackDir)
        val lockState = try {
            if (installationLock.exists()) JSONObject(installationLock.readText()) else null
        } catch (_: Exception) {
            null
        }
        val phase = lockState?.optString("phase")
        val hadCurrentRootfs = lockState?.optBoolean("hadCurrentRootfs", true) ?: true
        when (RootfsTransactionPolicy.recoveryAction(
            phase = phase,
            hadCurrentRootfs = hadCurrentRootfs,
            rollbackExists = rollback.exists(),
        )) {
            RootfsRecoveryAction.RESTORE_ROLLBACK -> {
                val failed = File("$rootfsStagingDir-failed")
                if (failed.exists()) deleteRecursively(failed)
                failed.parentFile?.mkdirs()
                if (current.exists() && !current.renameTo(failed)) {
                    throw RuntimeException(
                        "Unable to move failed rootfs aside before rollback"
                    )
                }
                current.parentFile?.mkdirs()
                if (!rollback.renameTo(current)) {
                    if (failed.exists()) failed.renameTo(current)
                    throw RuntimeException(
                        "Unable to restore previous rootfs; failed rootfs was put back"
                    )
                }
                if (failed.exists()) deleteRecursively(failed)
            }
            RootfsRecoveryAction.DELETE_UNCOMMITTED_ROOTFS -> {
                if (current.exists()) deleteRecursively(current)
            }
            RootfsRecoveryAction.KEEP_CURRENT_ROOTFS -> Unit
        }
        val staging = File(rootfsStagingDir)
        if (staging.exists()) deleteRecursively(staging)
        installationLock.delete()
    }

    @Synchronized
    fun recoverInterruptedRootfsInstall() {
        if (!installationLock.exists()) return
        rollbackRootfsInstall()
    }

    /**
     * Extract all .deb packages from the apt cache into the rootfs.
     * Uses Java (Apache Commons Compress) to avoid fork+exec issues in proot.
     * A .deb is an ar archive containing data.tar.{xz,gz,zst}.
     * Returns the number of packages extracted.
     */
    fun extractDebPackages(): Int {
        val archivesDir = File("$rootfsDir/var/cache/apt/archives")
        if (!archivesDir.exists()) {
            throw RuntimeException("No apt archives directory found")
        }

        val debFiles = archivesDir.listFiles { f -> f.name.endsWith(".deb") }
            ?: throw RuntimeException("No .deb files found in apt cache")

        if (debFiles.isEmpty()) {
            throw RuntimeException("No .deb files found in apt cache")
        }

        var extracted = 0
        val errors = mutableListOf<String>()

        for (debFile in debFiles) {
            try {
                extractSingleDeb(debFile)
                extracted++
            } catch (e: Exception) {
                errors.add("${debFile.name}: ${e.message}")
            }
        }

        if (extracted == 0) {
            throw RuntimeException(
                "Failed to extract any .deb packages. Errors: ${errors.joinToString("; ")}"
            )
        }

        // Fix permissions on newly extracted binaries
        fixBinPermissions()

        return extracted
    }

    /**
     * Extract a single .deb file into the rootfs.
     * Reads the ar archive, finds data.tar.*, decompresses, and extracts.
     */
    private fun extractSingleDeb(debFile: File) {
        FileInputStream(debFile).use { fis ->
            BufferedInputStream(fis).use { bis ->
                ArArchiveInputStream(bis).use { arIn ->
                    var arEntry = arIn.nextEntry
                    while (arEntry != null) {
                        val name = arEntry.name
                        if (name.startsWith("data.tar")) {
                            // Wrap in appropriate decompressor
                            val dataStream: InputStream = when {
                                name.endsWith(".xz") -> XZCompressorInputStream(arIn)
                                name.endsWith(".gz") -> GZIPInputStream(arIn)
                                name.endsWith(".zst") -> ZstdCompressorInputStream(arIn)
                                else -> arIn // plain .tar or unknown
                            }

                            // Extract data.tar contents into rootfs
                            TarArchiveInputStream(dataStream).use { tarIn ->
                                var tarEntry = tarIn.nextEntry
                                while (tarEntry != null) {
                                    val entryName = tarEntry.name
                                        .removePrefix("./")
                                        .removePrefix("/")

                                    if (entryName.isEmpty()) {
                                        tarEntry = tarIn.nextEntry
                                        continue
                                    }

                                    val outFile = File(rootfsDir, entryName)

                                    when {
                                        tarEntry.isDirectory -> {
                                            outFile.mkdirs()
                                        }
                                        tarEntry.isSymbolicLink -> {
                                            try {
                                                if (outFile.exists()) outFile.delete()
                                                outFile.parentFile?.mkdirs()
                                                Os.symlink(tarEntry.linkName, outFile.absolutePath)
                                            } catch (_: Exception) {}
                                        }
                                        tarEntry.isLink -> {
                                            val target = tarEntry.linkName
                                                .removePrefix("./")
                                                .removePrefix("/")
                                            val targetFile = File(rootfsDir, target)
                                            outFile.parentFile?.mkdirs()
                                            try {
                                                if (targetFile.exists()) {
                                                    targetFile.copyTo(outFile, overwrite = true)
                                                    if (targetFile.canExecute()) {
                                                        outFile.setExecutable(true, false)
                                                    }
                                                }
                                            } catch (_: Exception) {}
                                        }
                                        else -> {
                                            outFile.parentFile?.mkdirs()
                                            FileOutputStream(outFile).use { fos ->
                                                val buf = ByteArray(65536)
                                                var len: Int
                                                while (tarIn.read(buf).also { len = it } != -1) {
                                                    fos.write(buf, 0, len)
                                                }
                                            }
                                            outFile.setReadable(true, false)
                                            outFile.setWritable(true, false)
                                            val mode = tarEntry.mode
                                            if (mode and 0b001_001_001 != 0) {
                                                outFile.setExecutable(true, false)
                                            }
                                            // Ensure bin/sbin files are executable
                                            val path = entryName.lowercase()
                                            if (path.contains("/bin/") ||
                                                path.contains("/sbin/")) {
                                                outFile.setExecutable(true, false)
                                            }
                                        }
                                    }

                                    tarEntry = tarIn.nextEntry
                                }
                            }
                            return // Found and processed data.tar, done
                        }
                        arEntry = arIn.nextEntry
                    }
                }
            }
        }
    }

    /**
     * Write configuration files that make the rootfs work correctly under proot.
     * Called automatically after extraction.
     */
    private fun configureRootfs() {
        // 1. Disable apt sandboxing 鈥?proot fakes UID 0 via ptrace but cannot
        //    intercept setresuid/setresgid, so apt's _apt user privilege drop
        //    fails with "Operation not permitted". Tell apt to stay as root.
        val aptConfDir = File("$rootfsDir/etc/apt/apt.conf.d")
        aptConfDir.mkdirs()
        File(aptConfDir, "01-openclaw-proot").writeText(
            "APT::Sandbox::User \"root\";\n" +
            "Acquire::Languages \"none\";\n" +
            "Acquire::Retries \"3\";\n" +
            "Acquire::http::Timeout \"20\";\n" +
            "Acquire::https::Timeout \"20\";\n" +
            // Disable PTY allocation when APT forks dpkg. APT's child process
            // calls SetupSlavePtyMagic() before execvp(dpkg); in proot on
            // Android 10+ (W^X policy), the PTY/chdir setup in the child can
            // fail causing _exit(100). Disabling this simplifies the fork path.
            "Dpkg::Use-Pty \"0\";\n" +
            // Pass dpkg options through apt to tolerate proot failures
            "Dpkg::Options { \"--force-confnew\"; \"--force-overwrite\"; };\n"
        )

        // 2. Configure dpkg for proot compatibility
        //    - force-unsafe-io: skip fsync/sync_file_range (may ENOSYS in proot)
        //    - no-debsig: skip signature verification
        val dpkgConfDir = File("$rootfsDir/etc/dpkg/dpkg.cfg.d")
        dpkgConfDir.mkdirs()
        File(dpkgConfDir, "01-openclaw-proot").writeText(
            "force-unsafe-io\n" +
            "no-debsig\n" +
            "force-overwrite\n" +
            "force-depends\n"
        )

        // 3. Ensure essential directories exist
        // mkdir syscall is broken inside proot on Android 10+.
        // Pre-create ALL directories that tools need at runtime.
        listOf(
            "$rootfsDir/etc/ssl/certs",
            "$rootfsDir/usr/share/keyrings",
            "$rootfsDir/etc/apt/sources.list.d",
            "$rootfsDir/var/cache/apt",
            "$rootfsDir/var/cache/apt/archives",
            "$rootfsDir/var/cache/apt/archives/partial",
            "$rootfsDir/var/lib/apt",
            "$rootfsDir/var/lib/apt/lists",
            "$rootfsDir/var/lib/apt/lists/partial",
            "$rootfsDir/var/log/apt",
            "$rootfsDir/var/lib/dpkg/updates",
            "$rootfsDir/var/lib/dpkg/triggers",
            // npm cache directories (npm can't mkdir inside proot)
            "$rootfsDir/tmp/npm-cache/_cacache/tmp",
            "$rootfsDir/tmp/npm-cache/_cacache/content-v2",
            "$rootfsDir/tmp/npm-cache/_cacache/index-v5",
            "$rootfsDir/tmp/npm-cache/_logs",
            // Node.js / npm working directories
            "$rootfsDir/root/.npm",
            "$rootfsDir/root/.config",
            "$rootfsDir/usr/local/lib/node_modules",
            "$rootfsDir/usr/local/bin",
            // OpenClaw runtime directories (can't mkdir at runtime)
            "$rootfsDir/root/.openclaw",
            "$rootfsDir/root/.openclaw/data",
            "$rootfsDir/root/.openclaw/memory",
            "$rootfsDir/root/.openclaw/skills",
            "$rootfsDir/root/.openclaw/config",
            "$rootfsDir/root/.openclaw/extensions",
            "$rootfsDir/root/.openclaw/logs",
            "$rootfsDir/root/.config/openclaw",
            "$rootfsDir/root/.local/share",
            "$rootfsDir/root/.cache",
            "$rootfsDir/root/.cache/openclaw",
            "$rootfsDir/root/.cache/node",
            // General runtime directories
            "$rootfsDir/var/tmp",
            "$rootfsDir/run",
            "$rootfsDir/run/lock",
            "$rootfsDir/dev/shm",
        ).forEach { File(it).mkdirs() }

        // 4. Ensure /etc/machine-id exists (dpkg triggers and systemd utils need it)
        val machineId = File("$rootfsDir/etc/machine-id")
        if (!machineId.exists()) {
            machineId.parentFile?.mkdirs()
            machineId.writeText("10000000000000000000000000000000\n")
        }

        // 4. Ensure policy-rc.d prevents services from auto-starting during install
        //    (they'd fail inside proot anyway)
        val policyRc = File("$rootfsDir/usr/sbin/policy-rc.d")
        policyRc.parentFile?.mkdirs()
        policyRc.writeText("#!/bin/sh\nexit 101\n")
        policyRc.setExecutable(true, false)

        // 5. Register Android user/groups in rootfs (matching proot-distro).
        //    dpkg and apt need valid user/group databases.
        registerAndroidUsers()

        // 6. Write /etc/hosts (some post-install scripts need hostname resolution)
        val hosts = File("$rootfsDir/etc/hosts")
        if (!hosts.exists() || !hosts.readText().contains("localhost")) {
            hosts.writeText(
                "127.0.0.1   localhost.localdomain localhost\n" +
                "::1         localhost.localdomain localhost ip6-localhost ip6-loopback\n"
            )
        }

        // 7. Ensure /tmp exists with world-writable + sticky permissions
        //    (needed for /dev/shm bind mount and general temp file usage)
        val tmpDir = File("$rootfsDir/tmp")
        tmpDir.mkdirs()
        tmpDir.setReadable(true, false)
        tmpDir.setWritable(true, false)
        tmpDir.setExecutable(true, false)

        // 8. Fix executable permissions on critical directories.
        //    Our Java extraction might not preserve all permission bits correctly
        //    (dpkg error 100 = "Could not exec dpkg" = permission issue).
        //    Recursively ensure all files in bin/sbin/lib dirs are executable.
        fixBinPermissions()
        ensureDefaultTimezone()
    }

    private fun ensureDefaultTimezone() {
        val rootfs = File(rootfsDir)
        if (!rootfs.exists()) {
            return
        }

        val timezone = "Asia/Shanghai"
        val timezoneFile = File("$rootfsDir/etc/timezone")
        timezoneFile.parentFile?.mkdirs()
        timezoneFile.writeText("$timezone\n")

        val zoneinfo = File("$rootfsDir/usr/share/zoneinfo/$timezone")
        if (!zoneinfo.exists()) {
            return
        }

        val localtime = File("$rootfsDir/etc/localtime")
        try {
            localtime.delete()
        } catch (_: Exception) {}

        try {
            Os.symlink("/usr/share/zoneinfo/$timezone", localtime.absolutePath)
        } catch (_: Exception) {
            try {
                zoneinfo.copyTo(localtime, overwrite = true)
            } catch (_: Exception) {}
        }
    }

    /**
     * Ensure all files in executable directories have the execute bit set.
     * Java's File API doesn't support full Unix permissions, so tar extraction
     * may leave some binaries without +x, causing "Could not exec dpkg" (error 100).
     */
    private fun fixBinPermissions() {
        // Directories whose files (recursively) must be executable
        val recursiveExecDirs = listOf(
            "$rootfsDir/usr/bin",
            "$rootfsDir/usr/sbin",
            "$rootfsDir/usr/local/bin",
            "$rootfsDir/usr/local/sbin",
            "$rootfsDir/usr/lib/apt/methods",
            "$rootfsDir/usr/lib/dpkg",
            "$rootfsDir/usr/lib/git-core",     // git sub-commands (git-remote-https, etc.)
            "$rootfsDir/usr/libexec",
            "$rootfsDir/var/lib/dpkg/info",    // dpkg maintainer scripts (preinst/postinst/prerm/postrm)
            "$rootfsDir/usr/share/debconf",    // debconf frontend scripts
            // These might be symlinks to usr/* in merged /usr, but
            // if they're real dirs we need to fix them too
            "$rootfsDir/bin",
            "$rootfsDir/sbin",
        )
        for (dirPath in recursiveExecDirs) {
            val dir = File(dirPath)
            if (dir.exists() && dir.isDirectory) {
                fixExecRecursive(dir)
            }
        }
        // Also fix shared libraries (dpkg, apt, etc. link against them)
        val libDirs = listOf(
            "$rootfsDir/usr/lib",
            "$rootfsDir/lib",
        )
        for (dirPath in libDirs) {
            val dir = File(dirPath)
            if (dir.exists() && dir.isDirectory) {
                fixSharedLibsRecursive(dir)
            }
        }
    }

    /** Recursively set +rx on all regular files in a directory tree. */
    private fun fixExecRecursive(dir: File) {
        dir.listFiles()?.forEach { file ->
            if (file.isDirectory) {
                fixExecRecursive(file)
            } else if (file.isFile) {
                file.setReadable(true, false)
                file.setExecutable(true, false)
            }
        }
    }

    private fun fixSharedLibsRecursive(dir: File) {
        dir.listFiles()?.forEach { file ->
            if (file.isDirectory) {
                fixSharedLibsRecursive(file)
            } else if (file.name.endsWith(".so") || file.name.contains(".so.")) {
                file.setReadable(true, false)
                file.setExecutable(true, false)
            }
        }
    }

    /**
     * Register Android UID/GID in the rootfs user databases,
     * matching what proot-distro does during installation.
     * This ensures dpkg/apt can resolve user/group names.
     */
    private fun registerAndroidUsers() {
        val uid = android.os.Process.myUid()
        val gid = uid // On Android, primary GID == UID

        // Ensure files are writable
        for (name in listOf("passwd", "shadow", "group", "gshadow")) {
            val f = File("$rootfsDir/etc/$name")
            if (f.exists()) f.setWritable(true, false)
        }

        // Add Android app user to /etc/passwd
        val passwd = File("$rootfsDir/etc/passwd")
        if (passwd.exists()) {
            val content = passwd.readText()
            if (!content.contains("aid_android")) {
                passwd.appendText("aid_android:x:$uid:$gid:Android:/:/sbin/nologin\n")
            }
        }

        // Add to /etc/shadow
        val shadow = File("$rootfsDir/etc/shadow")
        if (shadow.exists()) {
            val content = shadow.readText()
            if (!content.contains("aid_android")) {
                shadow.appendText("aid_android:*:18446:0:99999:7:::\n")
            }
        }

        // Add Android groups to /etc/group
        val group = File("$rootfsDir/etc/group")
        if (group.exists()) {
            val content = group.readText()
            // Add common Android groups that packages might reference
            val groups = mapOf(
                "aid_inet" to 3003,       // Internet access
                "aid_net_raw" to 3004,    // Raw sockets
                "aid_sdcard_rw" to 1015,  // SD card write
                "aid_android" to gid,     // App's own group
            )
            for ((name, id) in groups) {
                if (!content.contains(name)) {
                    group.appendText("$name:x:$id:root,aid_android\n")
                }
            }
        }

        // Add to /etc/gshadow
        val gshadow = File("$rootfsDir/etc/gshadow")
        if (gshadow.exists()) {
            val content = gshadow.readText()
            val groups = listOf("aid_inet", "aid_net_raw", "aid_sdcard_rw", "aid_android")
            for (name in groups) {
                if (!content.contains(name)) {
                    gshadow.appendText("$name:*::root,aid_android\n")
                }
            }
        }
    }

    /**
     * Extract a Node.js binary tarball (.tar.xz) into the rootfs.
     * The tarball contains node-v24.x.x-linux-arm64/ with bin/, lib/, etc.
     * We extract its contents into /usr/local/ so node and npm are on PATH.
     * This bypasses the NodeSource repo (curl/gpg fail in proot).
     */
    fun extractNodeTarball(tarPath: String) {
        val destDir = File("$rootfsDir/usr/local")
        destDir.mkdirs()

        var entryCount = 0
        try {
            FileInputStream(tarPath).use { fis ->
                BufferedInputStream(fis, 256 * 1024).use { bis ->
                    XZCompressorInputStream(bis).use { xzis ->
                        TarArchiveInputStream(xzis).use { tis ->
                            var entry: TarArchiveEntry? = tis.nextEntry
                            while (entry != null) {
                                entryCount++
                                val name = entry.name

                                // Strip the top-level directory (node-v24.x.x-linux-arm64/)
                                val slashIdx = name.indexOf('/')
                                if (slashIdx < 0 || slashIdx == name.length - 1) {
                                    entry = tis.nextEntry
                                    continue
                                }
                                val relPath = name.substring(slashIdx + 1)
                                if (relPath.isEmpty()) {
                                    entry = tis.nextEntry
                                    continue
                                }

                                val outFile = File(destDir, relPath)

                                when {
                                    entry.isDirectory -> {
                                        outFile.mkdirs()
                                    }
                                    entry.isSymbolicLink -> {
                                        try {
                                            if (outFile.exists()) outFile.delete()
                                            outFile.parentFile?.mkdirs()
                                            Os.symlink(entry.linkName, outFile.absolutePath)
                                        } catch (_: Exception) {}
                                    }
                                    else -> {
                                        outFile.parentFile?.mkdirs()
                                        FileOutputStream(outFile).use { fos ->
                                            val buf = ByteArray(65536)
                                            var len: Int
                                            while (tis.read(buf).also { len = it } != -1) {
                                                fos.write(buf, 0, len)
                                            }
                                        }
                                        outFile.setReadable(true, false)
                                        outFile.setWritable(true, false)
                                        // Set executable for bin/ files and .so files
                                        val mode = entry.mode
                                        if (mode and 0b001_001_001 != 0 ||
                                            relPath.startsWith("bin/") ||
                                            relPath.contains(".so")) {
                                            outFile.setExecutable(true, false)
                                        }
                                    }
                                }

                                entry = tis.nextEntry
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            throw RuntimeException(
                "Node.js tarball extraction failed after $entryCount entries: ${e.message}"
            )
        }

        // Verify node binary exists
        val nodeBin = File("$rootfsDir/usr/local/bin/node")
        if (!nodeBin.exists()) {
            throw RuntimeException(
                "Node.js extraction failed: node binary not found at /usr/local/bin/node " +
                "(processed $entryCount entries)"
            )
        }
        nodeBin.setExecutable(true, false)

        // Clean up tarball
        File(tarPath).delete()
    }

    /**
     * Create shell wrapper scripts in /usr/local/bin/ for a globally-installed
     * npm package. npm's `install -g` creates symlinks, but symlinks can fail
     * silently in proot. Shell wrappers are a reliable fallback.
     *
     * Reads the package.json `bin` field directly from the rootfs filesystem
     * (no shell escaping needed).
     */
    fun createBinWrappers(packageName: String, force: Boolean = false) {
        val pkgDir = File("$rootfsDir/usr/local/lib/node_modules/$packageName")
        val pkgJson = File(pkgDir, "package.json")
        if (!pkgJson.exists()) {
            throw RuntimeException("Package not found: $pkgDir")
        }

        // Simple JSON parsing for the "bin" field
        val json = pkgJson.readText()
        val binDir = File("$rootfsDir/usr/local/bin")
        binDir.mkdirs()

        // Parse bin entries from package.json
        // "bin": "cli.js"  OR  "bin": {"openclaw": "bin/openclaw.js", ...}
        val binEntries = mutableMapOf<String, String>()

        val binMatch = Regex(""""bin"\s*:\s*(\{[^}]*\}|"[^"]*")""").find(json)
        if (binMatch != null) {
            val value = binMatch.groupValues[1]
            if (value.startsWith("{")) {
                // Object: {"name": "path", ...}
                Regex(""""([^"]+)"\s*:\s*"([^"]+)"""").findAll(value).forEach {
                    binEntries[it.groupValues[1]] = it.groupValues[2]
                }
            } else {
                // String: "path" 鈥?use package name as bin name
                val path = value.trim('"')
                binEntries[packageName] = path
            }
        }

        if (binEntries.isEmpty()) {
            // Fallback: check for common entry points
            for (candidate in listOf("bin/$packageName.js", "bin/$packageName", "cli.js", "index.js")) {
                if (File(pkgDir, candidate).exists()) {
                    binEntries[packageName] = candidate
                    break
                }
            }
        }

        for ((name, relPath) in binEntries) {
            val binFile = File(binDir, name)
            // Only create wrapper if the symlink doesn't already work
            if (!force && binFile.exists() && binFile.canExecute()) continue

            // 修复模式允许替换损坏的 symlink 或旧 wrapper，仅作用于命令文件。
            try {
                java.nio.file.Files.deleteIfExists(binFile.toPath())
            } catch (_: Exception) {
                if (binFile.exists() && !binFile.delete()) {
                    throw RuntimeException("Cannot replace command wrapper: $binFile")
                }
            }

            val target = "/usr/local/lib/node_modules/$packageName/$relPath"
            val wrapper = "#!/bin/sh\nexec node \"$target\" \"\$@\"\n"
            binFile.writeText(wrapper)
            binFile.setExecutable(true, false)
            binFile.setReadable(true, false)
        }
    }

    private fun deleteRecursively(file: File) {
        // CRITICAL: Do NOT follow symlinks 鈥?the rootfs contains symlinks
        // to /storage/emulated/0 (sdcard). Following them would delete the
        // user's photos, downloads, and other real files.

        // Path boundary check: refuse to delete anything outside filesDir.
        // This is a secondary safeguard against accidental data loss (#67, #63).
        try {
            val filesRoot = File(filesDir).canonicalFile.toPath()
            val target = file.absoluteFile.toPath().normalize()
            if (!target.startsWith(filesRoot)) {
                return
            }
        } catch (_: Exception) {
            return // 无法验证词法路径边界时，宁可保留文件也不冒险删除。
        }

        try {
            val path = file.toPath()
            if (java.nio.file.Files.isSymbolicLink(path)) {
                file.delete()
                return
            }
        } catch (_: Exception) {}
        if (file.isDirectory) {
            file.listFiles()?.forEach { deleteRecursively(it) }
        }
        file.delete()
    }

    fun installBionicBypass() {
        val bypassDir = File("$rootfsDir/root/.openclaw")
        bypassDir.mkdirs()

        // 1. CWD fix 鈥?proot's getcwd() syscall returns ENOSYS on Android 10+.
        //    process.cwd() is called by Node's CJS module resolver and npm.
        //    This MUST be loaded before any other module.
        val cwdFixContent = """
// OpenClaw CWD Fix - Auto-generated
// proot on Android 10+ returns ENOSYS for getcwd() syscall.
// Patch process.cwd to return /root on failure.
const _origCwd = process.cwd;
process.cwd = function() {
  try { return _origCwd.call(process); }
  catch(e) { return process.env.HOME || '/root'; }
};
""".trimIndent()
        File(bypassDir, "cwd-fix.js").writeText(cwdFixContent)

        // 2. Node wrapper 鈥?patches broken syscalls then runs the target script.
        //    Used during bootstrap (where NODE_OPTIONS must be unset).
        //    Usage: node /root/.openclaw/node-wrapper.js <script> [args...]
        val wrapperContent = """
// OpenClaw Node Wrapper - Auto-generated
// Patches broken proot syscalls, then loads the target script.
// Used for bootstrap-time npm operations.

// --- Load shared proot compatibility patches ---
require('/root/.openclaw/proot-compat.js');

// Load target script
const script = process.argv[2];
if (script) {
  process.argv = [process.argv[0], script, ...process.argv.slice(3)];
  require(script);
} else {
  console.log('Usage: node node-wrapper.js <script> [args...]');
  process.exit(1);
}
""".trimIndent()
        File(bypassDir, "node-wrapper.js").writeText(wrapperContent)

        // 3. Shared proot compatibility patches 鈥?used by both node-wrapper.js
        //    (bootstrap) and bionic-bypass.js (runtime).
        //    Patches: process.cwd, fs.mkdir, child_process.spawn, os.*, fs.rename,
        //    fs.watch, fs.chmod/chown.
        val prootCompatContent = """
// OpenClaw Proot Compatibility Layer - Auto-generated
// Patches all known broken syscalls in proot on Android 10+.
// This file is require()'d by both node-wrapper.js and bionic-bypass.js.

'use strict';

// ====================================================================
// 1. process.cwd() 鈥?getcwd() returns ENOSYS in proot
// ====================================================================
const _origCwd = process.cwd;
process.cwd = function() {
  try { return _origCwd.call(process); }
  catch(e) { return process.env.HOME || '/root'; }
};

// ====================================================================
// 2. os module patches 鈥?various /proc reads fail in proot
// ====================================================================
const _os = require('os');

// os.hostname() 鈥?may fail reading /proc/sys/kernel/hostname
const _origHostname = _os.hostname;
_os.hostname = function() {
  try { return _origHostname.call(_os); }
  catch(e) { return 'localhost'; }
};

// os.tmpdir() 鈥?ensure it returns /tmp
const _origTmpdir = _os.tmpdir;
_os.tmpdir = function() {
  try {
    const t = _origTmpdir.call(_os);
    return t || '/tmp';
  } catch(e) { return '/tmp'; }
};

// os.homedir() 鈥?may fail with ENOSYS
const _origHomedir = _os.homedir;
_os.homedir = function() {
  try { return _origHomedir.call(_os); }
  catch(e) { return process.env.HOME || '/root'; }
};

// os.userInfo() 鈥?getpwuid may fail in proot
const _origUserInfo = _os.userInfo;
_os.userInfo = function(opts) {
  try { return _origUserInfo.call(_os, opts); }
  catch(e) {
    return {
      uid: 0, gid: 0,
      username: 'root',
      homedir: process.env.HOME || '/root',
      shell: '/bin/bash'
    };
  }
};

// os.cpus() 鈥?reading /proc/cpuinfo may fail
const _origCpus = _os.cpus;
_os.cpus = function() {
  try {
    const cpus = _origCpus.call(_os);
    if (cpus && cpus.length > 0) return cpus;
  } catch(e) {}
  return [{ model: 'ARM', speed: 2000, times: { user: 0, nice: 0, sys: 0, idle: 0, irq: 0 } }];
};

// os.totalmem() / os.freemem() 鈥?reading /proc/meminfo may fail
const _origTotalmem = _os.totalmem;
_os.totalmem = function() {
  try { return _origTotalmem.call(_os); }
  catch(e) { return 4 * 1024 * 1024 * 1024; } // 4GB fallback
};
const _origFreemem = _os.freemem;
_os.freemem = function() {
  try { return _origFreemem.call(_os); }
  catch(e) { return 2 * 1024 * 1024 * 1024; } // 2GB fallback
};

// os.networkInterfaces() 鈥?Android blocks getifaddrs()
const _origNetIf = _os.networkInterfaces;
_os.networkInterfaces = function() {
  try {
    const ifaces = _origNetIf.call(_os);
    if (ifaces && Object.keys(ifaces).length > 0) return ifaces;
  } catch(e) {}
  return {};
};

// ====================================================================
// 3. fs.mkdir 鈥?mkdirat() returns ENOSYS in proot
// ====================================================================
const _fs = require('fs');
const _path = require('path');
const _origMkdirSync = _fs.mkdirSync;
_fs.mkdirSync = function(p, options) {
  try {
    return _origMkdirSync.call(_fs, p, options);
  } catch(e) {
    if (e.code === 'ENOSYS' || (e.code === 'ENOENT' && options && options.recursive)) {
      const parts = _path.resolve(String(p)).split(_path.sep).filter(Boolean);
      let current = '';
      for (const part of parts) {
        current += _path.sep + part;
        try { _origMkdirSync.call(_fs, current); }
        catch(e2) { if (e2.code !== 'EEXIST' && e2.code !== 'EISDIR') { /* skip */ } }
      }
      return undefined;
    }
    throw e;
  }
};
const _origMkdir = _fs.mkdir;
_fs.mkdir = function(p, options, cb) {
  if (typeof options === 'function') { cb = options; options = undefined; }
  try { _fs.mkdirSync(p, options); if (cb) cb(null); }
  catch(e) { if (cb) cb(e); else throw e; }
};
const _fsp = _fs.promises;
if (_fsp) {
  const _origMkdirP = _fsp.mkdir;
  _fsp.mkdir = async function(p, options) {
    try { return await _origMkdirP.call(_fsp, p, options); }
    catch(e) {
      if (e.code === 'ENOSYS' || (e.code === 'ENOENT' && options && options.recursive)) {
        _fs.mkdirSync(p, options); return undefined;
      }
      throw e;
    }
  };
}

// ====================================================================
// 4. fs.rename 鈥?renameat2() may ENOSYS in proot; fallback to copy+unlink
// ====================================================================
const _origRenameSync = _fs.renameSync;
_fs.renameSync = function(oldPath, newPath) {
  try { return _origRenameSync.call(_fs, oldPath, newPath); }
  catch(e) {
    if (e.code === 'ENOSYS' || e.code === 'EXDEV') {
      _fs.copyFileSync(oldPath, newPath);
      try { _fs.unlinkSync(oldPath); } catch(_) {}
      return;
    }
    throw e;
  }
};
const _origRename = _fs.rename;
_fs.rename = function(oldPath, newPath, cb) {
  _origRename.call(_fs, oldPath, newPath, function(err) {
    if (err && (err.code === 'ENOSYS' || err.code === 'EXDEV')) {
      try {
        _fs.copyFileSync(oldPath, newPath);
        try { _fs.unlinkSync(oldPath); } catch(_) {}
        if (cb) cb(null);
      } catch(e2) { if (cb) cb(e2); }
    } else { if (cb) cb(err); }
  });
};
if (_fsp) {
  const _origRenameP = _fsp.rename;
  _fsp.rename = async function(oldPath, newPath) {
    try { return await _origRenameP.call(_fsp, oldPath, newPath); }
    catch(e) {
      if (e.code === 'ENOSYS' || e.code === 'EXDEV') {
        await _fsp.copyFile(oldPath, newPath);
        try { await _fsp.unlink(oldPath); } catch(_) {}
        return;
      }
      throw e;
    }
  };
}

// ====================================================================
// 5. fs.chmod/chown 鈥?fchmodat/fchownat may fail; tolerate ENOSYS
// ====================================================================
for (const fn of ['chmod', 'chown', 'lchown']) {
  const origSync = _fs[fn + 'Sync'];
  if (origSync) {
    _fs[fn + 'Sync'] = function() {
      try { return origSync.apply(_fs, arguments); }
      catch(e) { if (e.code === 'ENOSYS') return; throw e; }
    };
  }
  const origAsync = _fs[fn];
  if (origAsync) {
    _fs[fn] = function() {
      const args = Array.from(arguments);
      const cb = typeof args[args.length - 1] === 'function' ? args.pop() : null;
      try { origSync.apply(_fs, args); if (cb) cb(null); }
      catch(e) { if (e.code === 'ENOSYS') { if (cb) cb(null); } else { if (cb) cb(e); else throw e; } }
    };
  }
}

// ====================================================================
// 6. fs.watch 鈥?inotify may fail; provide silent no-op fallback
// ====================================================================
const _origWatch = _fs.watch;
_fs.watch = function(filename, options, listener) {
  try { return _origWatch.call(_fs, filename, options, listener); }
  catch(e) {
    if (e.code === 'ENOSYS' || e.code === 'ENOSPC' || e.code === 'ENOENT') {
      // Return a fake watcher that does nothing
      const EventEmitter = require('events');
      const fake = new EventEmitter();
      fake.close = function() {};
      fake.ref = function() { return this; };
      fake.unref = function() { return this; };
      return fake;
    }
    throw e;
  }
};

// ====================================================================
// 7. child_process.spawn 鈥?handle ENOSYS (proot) and ENOENT (missing binary).
//    Command-aware mock:
//    - Side-effect cmds (git, node-gyp, cmake, make): return FAILURE (128)
//      so npm doesn't look for files they were supposed to create
//    - Everything else: return SUCCESS (0) 鈥?npm internals proceed
//    Handles both ENOSYS (proot syscall fail) and ENOENT (binary not found,
//    e.g. git not installed in rootfs).
// ====================================================================
const _cp = require('child_process');
const _EventEmitter = require('events');

// Commands that produce side effects (files). Must return failure.
// Note: node-gyp, make, cmake are NOT mocked 鈥?python3/make/g++ are
// installed in the rootfs so native addon compilation works properly.
function _isSideEffectCmd(cmd) {
  const base = String(cmd).split('/').pop();
  return base === 'git' || base === 'cmake';
}

// Should this error be mocked? ENOSYS always, ENOENT for side-effect cmds.
function _shouldMock(errCode, cmd) {
  if (errCode === 'ENOSYS') return true;
  if (errCode === 'ENOENT' && _isSideEffectCmd(cmd)) return true;
  return false;
}

function _makeFakeChild(exitCode) {
  const fake = new _EventEmitter();
  fake.stdout = new (require('stream').Readable)({ read() { this.push(null); } });
  fake.stderr = new (require('stream').Readable)({ read() { this.push(null); } });
  fake.stdin = new (require('stream').Writable)({ write(c,e,cb) { cb(); } });
  fake.pid = 0;
  fake.exitCode = null;
  fake.kill = function() { return false; };
  fake.ref = function() { return this; };
  fake.unref = function() { return this; };
  fake.connected = false;
  fake.disconnect = function() {};
  process.nextTick(() => {
    fake.exitCode = exitCode;
    fake.emit('close', exitCode, null);
  });
  return fake;
}

function _makeFakeSyncResult(code) {
  return { status: code, signal: null, stdout: Buffer.alloc(0),
           stderr: Buffer.alloc(0),
           pid: 0, output: [null, Buffer.alloc(0), Buffer.alloc(0)],
           error: null };
}

const _origSpawn = _cp.spawn;
_cp.spawn = function(cmd, args, options) {
  try {
    const child = _origSpawn.call(_cp, cmd, args, options);
    child.on('error', (err) => {
      if (_shouldMock(err.code, cmd)) {
        const code = _isSideEffectCmd(cmd) ? 128 : 0;
        child.emit('close', code, null);
      }
    });
    return child;
  } catch(e) {
    if (_shouldMock(e.code, cmd)) {
      return _makeFakeChild(_isSideEffectCmd(cmd) ? 128 : 0);
    }
    throw e;
  }
};
const _origSpawnSync = _cp.spawnSync;
_cp.spawnSync = function(cmd, args, options) {
  try {
    const r = _origSpawnSync.call(_cp, cmd, args, options);
    if (r.error && _shouldMock(r.error.code, cmd)) {
      return _makeFakeSyncResult(_isSideEffectCmd(cmd) ? 128 : 0);
    }
    return r;
  } catch(e) {
    if (_shouldMock(e.code, cmd)) {
      return _makeFakeSyncResult(_isSideEffectCmd(cmd) ? 128 : 0);
    }
    throw e;
  }
};
// Also patch exec/execFile which are wrappers around spawn
const _origExecFile = _cp.execFile;
_cp.execFile = function(file, args, options, cb) {
  if (typeof args === 'function') { cb = args; args = []; options = {}; }
  if (typeof options === 'function') { cb = options; options = {}; }
  try { return _origExecFile.call(_cp, file, args, options, cb); }
  catch(e) {
    if (_shouldMock(e.code, file)) {
      const code = _isSideEffectCmd(file) ? 128 : 0;
      if (cb) cb(code ? Object.assign(new Error('spawn failed'), {code:e.code}) : null, '', '');
      return;
    }
    throw e;
  }
};
const _origExecFileSync = _cp.execFileSync;
_cp.execFileSync = function(file, args, options) {
  try { return _origExecFileSync.call(_cp, file, args, options); }
  catch(e) {
    if (_shouldMock(e.code, file)) {
      if (_isSideEffectCmd(file)) throw e;
      return Buffer.alloc(0);
    }
    throw e;
  }
};
""".trimIndent()
        File(bypassDir, "proot-compat.js").writeText(prootCompatContent)

        // 4. Bionic bypass 鈥?comprehensive runtime patcher for openclaw.
        //    Loaded via NODE_OPTIONS="--require /root/.openclaw/bionic-bypass.js"
        val bypassContent = """
// OpenClaw Bionic Bypass - Auto-generated
// Comprehensive runtime compatibility layer for proot on Android 10+.
// Loaded via NODE_OPTIONS before any application code runs.

// Load all proot compatibility patches (shared with node-wrapper.js)
require('/root/.openclaw/proot-compat.js');
""".trimIndent()

        File(bypassDir, "bionic-bypass.js").writeText(bypassContent)

        // 5. Git config 鈥?write .gitconfig directly to rootfs to avoid shell
        //    quoting issues when running `git config` inside proot via bash -c.
        //    Rewrites SSH URLs to HTTPS (no SSH keys in proot).
        //    npm dependencies like @whiskeysockets/libsignal-node use git+ssh.
        val gitConfig = File("$rootfsDir/root/.gitconfig")
        gitConfig.writeText(
            "[url \"https://github.com/\"]\n" +
            "\tinsteadOf = ssh://git@github.com/\n" +
            "\tinsteadOf = git@github.com:\n" +
            "[advice]\n" +
            "\tdetachedHead = false\n"
        )

        // Patch .bashrc
        val bashrc = File("$rootfsDir/root/.bashrc")
        val exportLine = "export NODE_OPTIONS=\"--require /root/.openclaw/bionic-bypass.js\""

        val existing = if (bashrc.exists()) bashrc.readText() else ""
        if (!existing.contains("bionic-bypass")) {
            bashrc.appendText("\n# OpenClaw Bionic Bypass\n$exportLine\n")
        }
    }

    /**
     * Read DNS servers from Android's active network. Falls back to
     * public DNS servers if system DNS is unavailable (#60).
     */
    private fun getSystemDnsServers(): String {
        val fallbackServers = listOf("223.5.5.5", "119.29.29.29", "8.8.8.8")
        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            if (cm != null) {
                val network = cm.activeNetwork
                if (network != null) {
                    val linkProps: LinkProperties? = cm.getLinkProperties(network)
                    val dnsServers = linkProps?.dnsServers
                    if (dnsServers != null && dnsServers.isNotEmpty()) {
                        val servers = (dnsServers.mapNotNull { it.hostAddress } + fallbackServers)
                            .map { it.trim() }
                            .filter { it.isNotEmpty() }
                            .distinct()
                            .take(3)
                        return servers.joinToString("\n") { "nameserver $it" } + "\n"
                    }
                }
            }
        } catch (_: Exception) {}
        return fallbackServers.joinToString("\n") { "nameserver $it" } + "\n"
    }

    fun writeResolvConf() {
        val content = getSystemDnsServers()
        val resolvFile = HostFilesystem.ensureFileTargetReady(
            "$configDir/resolv.conf",
            "host resolv.conf"
        )
        resolvFile.writeText(content)

        // Also write directly into rootfs /etc/resolv.conf so DNS works
        // even if the bind-mount fails or hasn't been set up yet (#40).
        try {
            val rootfsResolv = HostFilesystem.ensureFileTargetReady(
                "$rootfsDir/etc/resolv.conf",
                "rootfs resolv.conf"
            )
            rootfsResolv.writeText(content)
        } catch (_: Exception) {}
    }

    /**
     * 创建升级事务。包目录使用同分区移动，工作区按受保护清单复制。
     * 任一步失败都会尝试回滚，且绝不触碰清单之外的用户路径。
     */
    fun beginOpenClawUpgrade(
        sourceVersion: String,
        targetVersion: String
    ): Map<String, Any> {
        setupDirectories()
        cleanupCompletedUpgradeTransactions()
        val pendingTransactionId = findPendingUpgradeTransactionId()
        if (pendingTransactionId != null) {
            throw IllegalStateException(
                "Pending upgrade transaction must be recovered first: $pendingTransactionId"
            )
        }
        val id = "${System.currentTimeMillis()}-${java.util.UUID.randomUUID()}"
        val transactionRoot = File("$filesDir/upgrade_transactions/$id")
        val workspaceBackup = File(transactionRoot, "workspace")
        val packageBackup = File(transactionRoot, "package/openclaw")
        val packageSource = File("$rootfsDir/usr/local/lib/node_modules/openclaw")
        val commandFile = File("$rootfsDir/usr/local/bin/openclaw")
        val backedUpEntries = JSONArray()

        try {
            workspaceBackup.mkdirs()
            workspaceBackupRelativePaths.forEach { relativePath ->
                val source = File(workspaceRootDir, relativePath)
                if (source.exists()) {
                    copyUpgradePath(source, File(workspaceBackup, relativePath))
                    backedUpEntries.put(relativePath)
                }
            }

            val commandJson = JSONObject()
            try {
                if (java.nio.file.Files.isSymbolicLink(commandFile.toPath())) {
                    commandJson.put("kind", "symlink")
                    commandJson.put(
                        "target",
                        java.nio.file.Files.readSymbolicLink(commandFile.toPath()).toString()
                    )
                } else if (commandFile.exists()) {
                    commandJson.put("kind", "file")
                    copyUpgradePath(commandFile, File(transactionRoot, "command/openclaw"))
                } else {
                    commandJson.put("kind", "missing")
                }
            } catch (_: Exception) {
                commandJson.put("kind", "missing")
            }

            val manifest = JSONObject().apply {
                put("id", id)
                put("sourceVersion", sourceVersion.trim())
                put("targetVersion", targetVersion.trim())
                put("createdAt", java.time.Instant.now().toString())
                put("phase", "prepared")
                put("packageOriginallyPresent", packageSource.exists())
                put("workspaceEntries", backedUpEntries)
                put("command", commandJson)
            }
            File(transactionRoot, "manifest.json").writeText(manifest.toString(2))

            // 清单必须先于第一次破坏性移动落盘，进程在任意时刻终止都能找到回滚入口。
            if (packageSource.exists()) {
                moveUpgradePath(packageSource, packageBackup)
            }

            // npm 安装会重新创建 openclaw 命令；旧命令必须在事务清单落盘后移走，
            // 否则版本切换会在最后的 bin 链接阶段因 EEXIST 失败。
            try {
                java.nio.file.Files.deleteIfExists(commandFile.toPath())
            } catch (error: Exception) {
                if (!commandFile.delete() &&
                    (commandFile.exists() || java.nio.file.Files.isSymbolicLink(commandFile.toPath()))) {
                    throw error
                }
            }

            return hashMapOf(
                "id" to id,
                "backupPath" to transactionRoot.absolutePath,
                "workspaceEntries" to jsonArrayToStringList(backedUpEntries)
            )
        } catch (error: Exception) {
            try {
                if (File(transactionRoot, "manifest.json").exists()) {
                    rollbackOpenClawUpgrade(id)
                } else {
                    if (packageBackup.exists() && !packageSource.exists()) {
                        moveUpgradePath(packageBackup, packageSource)
                    }
                    deleteRecursively(transactionRoot)
                }
            } catch (_: Exception) {}
            throw RuntimeException("Failed to prepare upgrade transaction: ${error.message}")
        }
    }

    fun commitOpenClawUpgrade(id: String, reportJson: String?) {
        val transactionRoot = resolveUpgradeTransaction(id)
        val manifestFile = File(transactionRoot, "manifest.json")
        val manifest = if (manifestFile.exists()) {
            JSONObject(manifestFile.readText())
        } else {
            JSONObject().put("id", id)
        }
        val sourceVersion = manifest.optString("sourceVersion").trim()
        val packageBackup = File(transactionRoot, "package/openclaw")
        if (sourceVersion.isNotEmpty() && packageBackup.exists()) {
            val cachedPackage = cachedOpenClawPackage(sourceVersion)
            if (cachedPackage.parentFile?.exists() == true) {
                deleteRecursively(cachedPackage.parentFile!!)
            }
            cachedPackage.parentFile?.mkdirs()
            moveUpgradePath(packageBackup, cachedPackage)
            cachedPackage.parentFile?.setLastModified(System.currentTimeMillis())
            manifest.put("cachedSourceVersion", sourceVersion)
            trimOpenClawVersionCache()
        }
        manifest.put("phase", "committed")
        manifest.put("committedAt", java.time.Instant.now().toString())
        if (!reportJson.isNullOrBlank()) {
            try {
                manifest.put("report", JSONObject(reportJson))
            } catch (_: Exception) {
                manifest.put("report", reportJson.take(16_384))
            }
        }

        val historyDir = File("$filesDir/upgrade_history")
        historyDir.mkdirs()
        File(historyDir, "$id.json").writeText(manifest.toString(2))
        deleteRecursively(transactionRoot)
        cleanupCompletedUpgradeTransactions()
    }

    /** 持久化事务中间阶段，供中断恢复和历史审计定位失败位置。 */
    fun updateOpenClawUpgrade(id: String, phase: String, detailsJson: String?) {
        val allowedPhases = setOf(
            "prepared",
            "packageInstalled",
            "doctorChecked",
            "configMerged",
            "verified",
        )
        if (phase !in allowedPhases) {
            throw IllegalArgumentException("Invalid upgrade transaction phase: $phase")
        }
        val transactionRoot = resolveUpgradeTransaction(id)
        val manifestFile = File(transactionRoot, "manifest.json")
        if (!manifestFile.exists()) {
            throw IllegalArgumentException("Upgrade transaction manifest not found: $id")
        }
        val manifest = JSONObject(manifestFile.readText())
        val currentPhase = manifest.optString("phase")
        if (currentPhase == "committed" || currentPhase == "rolledBack") {
            throw IllegalStateException("Upgrade transaction is already complete: $id")
        }
        manifest.put("phase", phase)
        val updatedAt = java.time.Instant.now().toString()
        manifest.put("updatedAt", updatedAt)
        if (!detailsJson.isNullOrBlank()) {
            val details = try {
                JSONObject(detailsJson)
            } catch (_: Exception) {
                detailsJson.take(16_384)
            }
            manifest.put("phaseDetails", details)
            val phaseHistory = manifest.optJSONObject("phaseHistory") ?: JSONObject()
            phaseHistory.put(
                phase,
                JSONObject().apply {
                    put("updatedAt", updatedAt)
                    put("details", details)
                }
            )
            manifest.put("phaseHistory", phaseHistory)
        }
        manifestFile.writeText(manifest.toString(2))
    }

    fun validateOpenClawUpgrade(id: String): Map<String, Any> {
        val transactionRoot = resolveUpgradeTransaction(id)
        val manifestFile = File(transactionRoot, "manifest.json")
        if (!manifestFile.exists()) {
            throw IllegalArgumentException("Upgrade transaction manifest not found: $id")
        }
        val manifest = JSONObject(manifestFile.readText())
        val missing = ArrayList<String>()
        val entries = manifest.optJSONArray("workspaceEntries") ?: JSONArray()
        for (index in 0 until entries.length()) {
            val relativePath = entries.optString(index)
            if (relativePath.isNotBlank() && !File(workspaceRootDir, relativePath).exists()) {
                missing.add(relativePath)
            }
        }
        if (!File("$rootfsDir/usr/local/lib/node_modules/openclaw/package.json").exists()) {
            missing.add("package.json")
        }
        if (!File("$rootfsDir/usr/local/bin/openclaw").exists()) {
            missing.add("openclaw-command")
        }
        return hashMapOf(
            "valid" to missing.isEmpty(),
            "missing" to missing
        )
    }

    fun rollbackOpenClawUpgrade(id: String) {
        val transactionRoot = resolveUpgradeTransaction(id)
        val manifestFile = File(transactionRoot, "manifest.json")
        if (!manifestFile.exists()) {
            throw IllegalArgumentException("Upgrade transaction manifest not found: $id")
        }
        val manifest = JSONObject(manifestFile.readText())
        val packageTarget = File("$rootfsDir/usr/local/lib/node_modules/openclaw")
        val packageBackup = File(transactionRoot, "package/openclaw")

        val packageOriginallyPresent = manifest.optBoolean(
            "packageOriginallyPresent",
            packageBackup.exists()
        )
        if (packageBackup.exists()) {
            val cachedTargetVersion = manifest.optString("restoredFromVersionCache").trim()
            if (cachedTargetVersion.isNotEmpty() && packageTarget.exists()) {
                val cachedTarget = cachedOpenClawPackage(cachedTargetVersion)
                if (cachedTarget.parentFile?.exists() == true) {
                    deleteRecursively(cachedTarget.parentFile!!)
                }
                cachedTarget.parentFile?.mkdirs()
                moveUpgradePath(packageTarget, cachedTarget)
                cachedTarget.parentFile?.setLastModified(System.currentTimeMillis())
            } else if (packageTarget.exists()) {
                deleteRecursively(packageTarget)
            }
            moveUpgradePath(packageBackup, packageTarget)
        } else if (packageOriginallyPresent && !packageTarget.exists()) {
            // 清单已落盘但备份和原包都不存在时无法证明可恢复，禁止继续破坏工作区。
            throw IllegalStateException("Original OpenClaw package backup is missing")
        }

        // 回滚时只清理受保护目标，再从事务备份恢复原始内容。
        workspaceBackupRelativePaths.forEach { relativePath ->
            val target = File(workspaceRootDir, relativePath)
            if (target.exists()) deleteRecursively(target)
            val backup = File(transactionRoot, "workspace/$relativePath")
            if (backup.exists()) copyUpgradePath(backup, target)
        }

        val commandFile = File("$rootfsDir/usr/local/bin/openclaw")
        try {
            java.nio.file.Files.deleteIfExists(commandFile.toPath())
        } catch (_: Exception) {
            commandFile.delete()
        }
        val command = manifest.optJSONObject("command")
        when (command?.optString("kind")) {
            "symlink" -> {
                commandFile.parentFile?.mkdirs()
                Os.symlink(command.optString("target"), commandFile.absolutePath)
            }
            "file" -> copyUpgradePath(
                File(transactionRoot, "command/openclaw"),
                commandFile
            )
            else -> if (packageTarget.exists()) createBinWrappers("openclaw", force = true)
        }

        installBionicBypass()
        writeResolvConf()
        manifest.put("rolledBackFromPhase", manifest.optString("phase", "prepared"))
        manifest.put("phase", "rolledBack")
        manifest.put("rolledBackAt", java.time.Instant.now().toString())
        val historyDir = File("$filesDir/upgrade_history")
        historyDir.mkdirs()
        File(historyDir, "$id.json").writeText(manifest.toString(2))
        deleteRecursively(transactionRoot)
        cleanupCompletedUpgradeTransactions()
    }

    fun hasCachedOpenClawVersion(version: String): Boolean {
        return File(cachedOpenClawPackage(version), "package.json").exists()
    }

    /**
     * Restores a previously installed package by renaming it back into the
     * rootfs. beginOpenClawUpgrade must have moved the current package away
     * first; commit then places that previous package into this cache slot.
     */
    fun restoreCachedOpenClawVersion(id: String, version: String): Int {
        val transactionRoot = resolveUpgradeTransaction(id)
        val manifestFile = File(transactionRoot, "manifest.json")
        if (!manifestFile.exists()) {
            throw IllegalArgumentException("Upgrade transaction manifest not found: $id")
        }
        val manifest = JSONObject(manifestFile.readText())
        if (manifest.optString("targetVersion").trim() != version.trim()) {
            throw IllegalArgumentException("Cached version does not match transaction target")
        }
        val cachedPackage = cachedOpenClawPackage(version)
        if (!File(cachedPackage, "package.json").exists()) {
            throw IllegalStateException("Cached OpenClaw version is incomplete: $version")
        }
        val packageTarget = File("$rootfsDir/usr/local/lib/node_modules/openclaw")
        if (packageTarget.exists()) deleteRecursively(packageTarget)
        moveUpgradePath(cachedPackage, packageTarget)
        cachedPackage.parentFile?.let { parent ->
            if (parent.listFiles()?.isEmpty() == true) parent.delete()
        }
        manifest.put("restoredFromVersionCache", version.trim())
        manifestFile.writeText(manifest.toString(2))
        return packageTarget.walkTopDown().count { it.isFile }
    }

    private fun cachedOpenClawPackage(version: String): File {
        val normalized = version.trim()
        if (!Regex("^[0-9A-Za-z._-]+$").matches(normalized)) {
            throw IllegalArgumentException("Invalid OpenClaw cache version")
        }
        return File("$filesDir/openclaw_version_cache/$normalized/openclaw")
    }

    private fun trimOpenClawVersionCache(maxVersions: Int = 2) {
        val root = File("$filesDir/openclaw_version_cache")
        val versions = root.listFiles()
            ?.filter { it.isDirectory }
            ?.sortedByDescending { it.lastModified() }
            ?: return
        versions.drop(maxVersions).forEach { deleteRecursively(it) }
    }

    private fun resolveUpgradeTransaction(id: String): File {
        val normalized = id.trim()
        if (!Regex("^[A-Za-z0-9._-]+$").matches(normalized)) {
            throw IllegalArgumentException("Invalid upgrade transaction id")
        }
        val root = File("$filesDir/upgrade_transactions").canonicalFile
        val target = File(root, normalized).canonicalFile
        if (target.parentFile != root) {
            throw IllegalArgumentException("Upgrade transaction escapes root")
        }
        return target
    }

    /** 返回任意非终态事务，完成历史不会触发启动回滚。 */
    private fun findPendingUpgradeTransactionId(): String? {
        val transactionRoot = File("$filesDir/upgrade_transactions")
        return transactionRoot.listFiles()
            ?.asSequence()
            ?.filter { it.isDirectory && Regex("^[A-Za-z0-9._-]+$").matches(it.name) }
            ?.mapNotNull { transaction ->
                val manifestFile = File(transaction, "manifest.json")
                val phase = try {
                    if (!manifestFile.exists()) return@mapNotNull null
                    JSONObject(manifestFile.readText()).optString("phase")
                } catch (_: Exception) {
                    return@mapNotNull null
                }
                if (phase != "committed" && phase != "rolledBack") transaction else null
            }
            ?.maxByOrNull { it.lastModified() }
            ?.name
    }

    /** 清理由旧版本遗留、但已有最终历史记录的事务目录，不触碰仍在进行的事务。 */
    private fun cleanupCompletedUpgradeTransactions() {
        val transactionRoot = File("$filesDir/upgrade_transactions")
        val historyRoot = File("$filesDir/upgrade_history")
        transactionRoot.listFiles()?.forEach { transaction ->
            if (!Regex("^[A-Za-z0-9._-]+$").matches(transaction.name)) {
                return@forEach
            }
            val history = File(historyRoot, "${transaction.name}.json")
            if (!history.exists()) return@forEach
            val phase = try {
                JSONObject(history.readText()).optString("phase")
            } catch (_: Exception) {
                ""
            }
            if (phase == "committed" || phase == "rolledBack") {
                deleteRecursively(transaction)
            }
        }
    }

    private fun moveUpgradePath(source: File, target: File) {
        target.parentFile?.mkdirs()
        try {
            java.nio.file.Files.move(
                source.toPath(),
                target.toPath(),
                java.nio.file.StandardCopyOption.ATOMIC_MOVE
            )
            return
        } catch (_: Exception) {}
        if (source.renameTo(target)) return
        copyUpgradePath(source, target)
        deleteRecursively(source)
    }

    private fun copyUpgradePath(source: File, target: File) {
        if (java.nio.file.Files.isSymbolicLink(source.toPath())) {
            target.parentFile?.mkdirs()
            val linkTarget = java.nio.file.Files.readSymbolicLink(source.toPath())
            java.nio.file.Files.deleteIfExists(target.toPath())
            java.nio.file.Files.createSymbolicLink(target.toPath(), linkTarget)
            return
        }
        if (source.isDirectory) {
            target.mkdirs()
            source.listFiles()?.forEach { child ->
                copyUpgradePath(child, File(target, child.name))
            }
            return
        }
        target.parentFile?.mkdirs()
        source.copyTo(target, overwrite = true)
        target.setReadable(true, false)
        target.setWritable(true, false)
        if (source.canExecute()) target.setExecutable(true, false)
    }

    private fun jsonArrayToStringList(array: JSONArray): ArrayList<String> {
        val result = ArrayList<String>()
        for (index in 0 until array.length()) {
            result.add(array.optString(index))
        }
        return result
    }

    fun exportWorkspaceBackup(
        output: OutputStream,
        appVersion: String,
        openClawVersion: String?
    ) {
        setupDirectories()
        val workspaceRoot = workspaceRootDir
        workspaceRoot.mkdirs()

        ZipOutputStream(BufferedOutputStream(output)).use { zip ->
            val manifest = JSONObject().apply {
                put("format", workspaceBackupFormat)
                put("schemaVersion", 1)
                put("appVersion", appVersion.trim())
                if (openClawVersion.isNullOrBlank()) {
                    put("openClawVersion", JSONObject.NULL)
                } else {
                    put("openClawVersion", openClawVersion.trim())
                }
                put("createdAt", java.time.Instant.now().toString())
                put("workspaceRoot", "/root/.openclaw")
                put(
                    "entries",
                    JSONArray().apply {
                        workspaceBackupRelativePaths.forEach { put(it) }
                    }
                )
            }

            zip.putNextEntry(ZipEntry(workspaceBackupManifestName))
            zip.write(manifest.toString(2).toByteArray(Charsets.UTF_8))
            zip.closeEntry()

            workspaceBackupRelativePaths.forEach { relativePath ->
                val target = File(workspaceRoot, relativePath)
                if (target.exists()) {
                    addWorkspaceBackupEntry(zip, target, relativePath)
                }
            }
        }
    }

    fun inspectWorkspaceBackup(path: String): Map<String, Any>? {
        val manifest = readWorkspaceBackupManifest(File(path)) ?: return null
        val entries = ArrayList<String>()
        val jsonEntries = manifest.optJSONArray("entries")
        if (jsonEntries != null) {
            for (index in 0 until jsonEntries.length()) {
                val value = jsonEntries.optString(index)
                if (value.isNotBlank()) {
                    entries.add(value)
                }
            }
        }

        return hashMapOf(
            "format" to manifest.optString("format", ""),
            "schemaVersion" to manifest.optInt("schemaVersion", 1),
            "appVersion" to manifest.optString("appVersion", ""),
            "openClawVersion" to manifest.optString("openClawVersion", ""),
            "createdAt" to manifest.optString("createdAt", ""),
            "entries" to entries
        )
    }

    fun restoreWorkspaceBackup(path: String) {
        val archiveFile = File(path)
        val manifest = readWorkspaceBackupManifest(archiveFile)
            ?: throw IllegalArgumentException(
                "Selected file is not an OpenClaw workspace backup"
            )

        if (manifest.optString("format") != workspaceBackupFormat) {
            throw IllegalArgumentException("Unsupported workspace backup format")
        }

        setupDirectories()
        val workspaceRoot = workspaceRootDir
        workspaceRoot.mkdirs()
        val workspaceCanonicalRoot = workspaceRoot.canonicalPath

        validateWorkspaceBackupArchive(archiveFile)
        clearWorkspaceBackupTargets()

        ZipFile(archiveFile).use { zip ->
            val entries = zip.entries()
            while (entries.hasMoreElements()) {
                val entry = entries.nextElement()
                val normalizedName = entry.name.replace('\\', '/')
                if (normalizedName == workspaceBackupManifestName) {
                    continue
                }
                if (!normalizedName.startsWith("workspace/")) {
                    throw IllegalArgumentException(
                        "Unsupported workspace backup entry: $normalizedName"
                    )
                }

                val relativePath = normalizedName
                    .removePrefix("workspace/")
                    .trim('/')
                if (relativePath.isEmpty()) {
                    continue
                }
                if (!isAllowedWorkspaceBackupPath(relativePath) ||
                    relativePath.contains("..") ||
                    relativePath.startsWith("/")
                ) {
                    throw IllegalArgumentException(
                        "Unsafe workspace backup entry: $normalizedName"
                    )
                }

                val outputFile = File(workspaceRoot, relativePath)
                outputFile.parentFile?.mkdirs()
                val canonicalOutput = outputFile.canonicalPath
                if (canonicalOutput != workspaceCanonicalRoot &&
                    !canonicalOutput.startsWith("$workspaceCanonicalRoot${File.separator}")
                ) {
                    throw IllegalArgumentException(
                        "Workspace backup entry escapes target directory: $normalizedName"
                    )
                }

                if (entry.isDirectory || normalizedName.endsWith("/")) {
                    outputFile.mkdirs()
                    continue
                }

                zip.getInputStream(entry).use { input ->
                    FileOutputStream(outputFile).use { fileOutput ->
                        input.copyTo(fileOutput)
                    }
                }
                outputFile.setReadable(true, false)
                outputFile.setWritable(true, false)
            }
        }

        setupDirectories()
        installBionicBypass()
        writeResolvConf()
    }

    private fun addWorkspaceBackupEntry(
        zip: ZipOutputStream,
        file: File,
        relativePath: String
    ) {
        val normalizedPath = relativePath.replace('\\', '/').trim('/')
        if (normalizedPath.isEmpty()) {
            return
        }

        try {
            if (java.nio.file.Files.isSymbolicLink(file.toPath())) {
                return
            }
        } catch (_: Exception) {}

        if (file.isDirectory) {
            zip.putNextEntry(ZipEntry("workspace/$normalizedPath/"))
            zip.closeEntry()
            file.listFiles()
                ?.sortedBy { it.name }
                ?.forEach { child ->
                    addWorkspaceBackupEntry(
                        zip,
                        child,
                        "$normalizedPath/${child.name}"
                    )
                }
            return
        }

        zip.putNextEntry(ZipEntry("workspace/$normalizedPath"))
        FileInputStream(file).use { input ->
            input.copyTo(zip)
        }
        zip.closeEntry()
    }

    private fun clearWorkspaceBackupTargets() {
        val workspaceRoot = workspaceRootDir
        workspaceBackupRelativePaths.forEach { relativePath ->
            val target = File(workspaceRoot, relativePath)
            if (target.exists()) {
                deleteRecursively(target)
            }
        }
    }

    private fun validateWorkspaceBackupArchive(archiveFile: File) {
        ZipFile(archiveFile).use { zip ->
            val entries = zip.entries()
            while (entries.hasMoreElements()) {
                val entry = entries.nextElement()
                val normalizedName = entry.name.replace('\\', '/')
                if (normalizedName == workspaceBackupManifestName) {
                    continue
                }
                if (!normalizedName.startsWith("workspace/")) {
                    throw IllegalArgumentException(
                        "Unsupported workspace backup entry: $normalizedName"
                    )
                }

                val relativePath = normalizedName
                    .removePrefix("workspace/")
                    .trim('/')
                if (relativePath.isEmpty()) {
                    continue
                }
                if (!isAllowedWorkspaceBackupPath(relativePath) ||
                    relativePath.contains("..") ||
                    relativePath.startsWith("/")
                ) {
                    throw IllegalArgumentException(
                        "Unsafe workspace backup entry: $normalizedName"
                    )
                }
            }
        }
    }

    private fun isAllowedWorkspaceBackupPath(relativePath: String): Boolean {
        return workspaceBackupRelativePaths.any { allowed ->
            relativePath == allowed || relativePath.startsWith("$allowed/")
        }
    }

    private fun readWorkspaceBackupManifest(archiveFile: File): JSONObject? {
        if (!archiveFile.exists() || !archiveFile.isFile) {
            return null
        }

        return try {
            ZipFile(archiveFile).use { zip ->
                val entry = zip.getEntry(workspaceBackupManifestName) ?: return null
                val content = zip.getInputStream(entry)
                    .bufferedReader(Charsets.UTF_8)
                    .use { it.readText() }
                val manifest = JSONObject(content)
                if (manifest.optString("format") == workspaceBackupFormat) {
                    manifest
                } else {
                    null
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    /** Read a file from inside the rootfs (e.g. /root/.openclaw/openclaw.json). */
    fun readRootfsFile(path: String): String? {
        val file = File("$rootfsDir/$path")
        return if (file.exists()) file.readText() else null
    }

    /** Write content to a file inside the rootfs, creating parent dirs as needed. */
    fun writeRootfsFile(path: String, content: String) {
        val file = File("$rootfsDir/$path")
        file.parentFile?.mkdirs()
        file.writeText(content)
    }

    fun copyBundledAssetToFile(assetPath: String, destinationPath: String) {
        val assetKey = FlutterInjector.instance()
            .flutterLoader()
            .getLookupKeyForAsset(assetPath)
        val destinationFile = File(destinationPath)
        destinationFile.parentFile?.mkdirs()

        try {
            context.assets.open(assetKey).use { input ->
                FileOutputStream(destinationFile).use { output ->
                    input.copyTo(output)
                }
            }
        } catch (e: FileNotFoundException) {
            throw RuntimeException("Bundled asset not found: $assetPath")
        }

        destinationFile.setReadable(true, false)
        destinationFile.setWritable(true, false)
    }

    /**
     * Restore only the bundled OpenClaw package from the full runtime archive.
     * The caller protects the existing package with an OpenClaw upgrade
     * transaction first, so this avoids replacing the whole rootfs merely to
     * switch back to the APK's built-in version.
     */
    fun restoreBundledOpenClawPackage(assetPath: String): Int {
        val assetKey = FlutterInjector.instance()
            .flutterLoader()
            .getLookupKeyForAsset(assetPath)
        val packagePrefix = "usr/local/lib/node_modules/openclaw"
        val packageRoot = File(rootfsDir, packagePrefix)
        val packageRootPath = packageRoot.canonicalPath
        val deferredSymlinks = mutableListOf<Pair<String, String>>()
        var extractedFiles = 0

        if (packageRoot.exists()) deleteRecursively(packageRoot)
        packageRoot.mkdirs()

        context.assets.open(assetKey).use { input ->
            BufferedInputStream(input, 256 * 1024).use { buffered ->
                GZIPInputStream(buffered).use { gzip ->
                    TarArchiveInputStream(gzip).use { tar ->
                        var entry: TarArchiveEntry? = tar.nextEntry
                        while (entry != null) {
                            val name = entry.name
                                .removePrefix("./")
                                .removePrefix("/")
                                .trimEnd('/')
                            if (name == packagePrefix ||
                                name.startsWith("$packagePrefix/")) {
                                val relative = name.removePrefix(packagePrefix).trimStart('/')
                                val output = if (relative.isEmpty()) {
                                    packageRoot
                                } else {
                                    File(packageRoot, relative)
                                }
                                val outputPath = output.canonicalPath
                                if (outputPath != packageRootPath &&
                                    !outputPath.startsWith(
                                        "$packageRootPath${File.separator}"
                                    )) {
                                    throw RuntimeException(
                                        "Unsafe bundled OpenClaw path: ${entry.name}"
                                    )
                                }

                                when {
                                    entry.isDirectory -> output.mkdirs()
                                    entry.isSymbolicLink -> {
                                        deferredSymlinks.add(entry.linkName to output.absolutePath)
                                    }
                                    entry.isLink -> {
                                        val linkName = entry.linkName
                                            .removePrefix("./")
                                            .removePrefix("/")
                                        if (linkName == packagePrefix ||
                                            linkName.startsWith("$packagePrefix/")) {
                                            val targetRelative = linkName
                                                .removePrefix(packagePrefix)
                                                .trimStart('/')
                                            val target = File(packageRoot, targetRelative)
                                            output.parentFile?.mkdirs()
                                            if (target.exists()) {
                                                target.copyTo(output, overwrite = true)
                                                extractedFiles++
                                            }
                                        }
                                    }
                                    else -> {
                                        output.parentFile?.mkdirs()
                                        FileOutputStream(output).use { stream ->
                                            val buffer = ByteArray(64 * 1024)
                                            var count: Int
                                            while (tar.read(buffer).also { count = it } != -1) {
                                                stream.write(buffer, 0, count)
                                            }
                                        }
                                        output.setReadable(true, false)
                                        output.setWritable(true, false)
                                        if (entry.mode and 0b001_001_001 != 0 ||
                                            relative.endsWith(".sh")) {
                                            output.setExecutable(true, false)
                                        }
                                        extractedFiles++
                                    }
                                }
                            }
                            entry = tar.nextEntry
                        }
                    }
                }
            }
        }

        for ((target, path) in deferredSymlinks) {
            val link = File(path)
            try {
                java.nio.file.Files.deleteIfExists(link.toPath())
            } catch (_: Exception) {
                if (link.exists()) deleteRecursively(link)
            }
            link.parentFile?.mkdirs()
            Os.symlink(target, path)
        }

        val packageJson = File(packageRoot, "package.json")
        if (extractedFiles == 0 || !packageJson.exists()) {
            if (packageRoot.exists()) deleteRecursively(packageRoot)
            throw RuntimeException(
                "Bundled runtime does not contain a complete OpenClaw package"
            )
        }
        return extractedFiles
    }

    /**
     * Create fake /proc and /sys files that are bind-mounted into proot.
     * Android restricts access to many /proc entries; proot-distro works
     * around this by providing static fake data. We replicate that approach.
     */
    fun setupFakeSysdata() {
        HostFilesystem.ensureDirectoryReady(configDir, "config directory")
        val procDir = HostFilesystem.ensureDirectoryReady(
            "$configDir/proc_fakes",
            "fake /proc directory"
        )
        val sysDir = HostFilesystem.ensureDirectoryReady(
            "$configDir/sys_fakes",
            "fake /sys directory"
        )

        // /proc/loadavg
        File(procDir, "loadavg").writeText("0.12 0.07 0.02 2/165 765\n")

        // /proc/stat 鈥?matching proot-distro (8 CPUs)
        File(procDir, "stat").writeText(
            "cpu  1957 0 2877 93280 262 342 254 87 0 0\n" +
            "cpu0 31 0 226 12027 82 10 4 9 0 0\n" +
            "cpu1 45 0 290 11498 21 9 8 7 0 0\n" +
            "cpu2 52 0 401 11730 36 15 6 10 0 0\n" +
            "cpu3 42 0 268 11677 31 12 5 8 0 0\n" +
            "cpu4 789 0 720 11364 26 100 83 18 0 0\n" +
            "cpu5 486 0 438 11685 42 86 60 13 0 0\n" +
            "cpu6 314 0 336 11808 45 68 52 11 0 0\n" +
            "cpu7 198 0 198 11491 25 42 36 11 0 0\n" +
            "intr 63361 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\n" +
            "ctxt 38014093\n" +
            "btime 1694292441\n" +
            "processes 26442\n" +
            "procs_running 1\n" +
            "procs_blocked 0\n" +
            "softirq 75663 0 5903 6 25375 10774 0 243 11685 0 21677\n"
        )

        // /proc/uptime
        File(procDir, "uptime").writeText("124.08 932.80\n")

        // /proc/version 鈥?fake kernel info matching proot-distro v4.37.0
        File(procDir, "version").writeText(
            "Linux version ${ProcessManager.FAKE_KERNEL_RELEASE} (proot@termux) " +
            "(gcc (GCC) 13.3.0, GNU ld (GNU Binutils) 2.42) " +
            "${ProcessManager.FAKE_KERNEL_VERSION}\n"
        )

        // /proc/vmstat 鈥?matching proot-distro format
        File(procDir, "vmstat").writeText(
            "nr_free_pages 1743136\n" +
            "nr_zone_inactive_anon 179281\n" +
            "nr_zone_active_anon 7183\n" +
            "nr_zone_inactive_file 22858\n" +
            "nr_zone_active_file 51328\n" +
            "nr_zone_unevictable 642\n" +
            "nr_zone_write_pending 0\n" +
            "nr_mlock 0\n" +
            "nr_slab_reclaimable 7520\n" +
            "nr_slab_unreclaimable 10776\n" +
            "pgpgin 198292\n" +
            "pgpgout 7674\n" +
            "pswpin 0\n" +
            "pswpout 0\n" +
            "pgalloc_dma 0\n" +
            "pgalloc_dma32 0\n" +
            "pgalloc_normal 44669136\n" +
            "pgfree 46674674\n" +
            "pgactivate 1085674\n" +
            "pgdeactivate 340776\n" +
            "pglazyfree 139872\n" +
            "pgfault 37291463\n" +
            "pgmajfault 6854\n" +
            "pgrefill 480634\n"
        )

        // /proc/sys/kernel/cap_last_cap
        File(procDir, "cap_last_cap").writeText("40\n")

        // /proc/sys/fs/inotify/max_user_watches
        File(procDir, "max_user_watches").writeText("4096\n")

        // /proc/sys/crypto/fips_enabled 鈥?libgcrypt reads this on startup;
        // missing/unreadable on Android causes apt HTTP method to SIGABRT
        File(procDir, "fips_enabled").writeText("0\n")

        // Empty file for /sys/fs/selinux bind
        File(sysDir, "empty").writeText("")
    }

    private fun checkNodeInProot(): Boolean {
        return try {
            val pm = ProcessManager(filesDir, nativeLibDir)
            val output = pm.runInProotSync("node --version")
            output.trim().startsWith("v")
        } catch (e: Exception) {
            false
        }
    }

    private fun checkOpenClawInProot(): Boolean {
        return try {
            val pm = ProcessManager(filesDir, nativeLibDir)
            val output = pm.runInProotSync("command -v openclaw")
            output.trim().isNotEmpty()
        } catch (e: Exception) {
            false
        }
    }
}

