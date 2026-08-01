package com.junwan666.openclawzh

import android.content.Context
import java.io.File

object NpmCacheManager {
    private const val PREFS_NAME = "openclaw_npm_cache"
    private const val KEY_LIMIT_MIB = "limit_mib"
    private const val KEY_DEFAULT_LIMIT_VERSION = "default_limit_version"
    private const val DEFAULT_LIMIT_VERSION = 2
    private const val PREVIOUS_DEFAULT_LIMIT_MIB = 512
    const val DEFAULT_LIMIT_MIB = 1024
    const val UNLIMITED = -1

    fun cacheDir(context: Context): File {
        val target = File(context.filesDir, "npm-cache")
        val legacy = File(context.filesDir, "rootfs/ubuntu/tmp/npm-cache")
        if (!target.exists() && legacy.exists()) {
            legacy.renameTo(target)
        }
        target.mkdirs()
        return target
    }

    fun getLimitMiB(context: Context): Int {
        val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val storedVersion = preferences.getInt(KEY_DEFAULT_LIMIT_VERSION, 1)
        val storedLimit = preferences.getInt(KEY_LIMIT_MIB, DEFAULT_LIMIT_MIB)
        if (storedVersion < DEFAULT_LIMIT_VERSION) {
            val migratedLimit = if (storedLimit == PREVIOUS_DEFAULT_LIMIT_MIB) {
                DEFAULT_LIMIT_MIB
            } else {
                storedLimit
            }
            preferences.edit()
                .putInt(KEY_LIMIT_MIB, migratedLimit)
                .putInt(KEY_DEFAULT_LIMIT_VERSION, DEFAULT_LIMIT_VERSION)
                .apply()
            return migratedLimit
        }
        return storedLimit
    }

    fun setLimitMiB(context: Context, limitMiB: Int) {
        require(limitMiB == UNLIMITED || limitMiB >= 0) { "Invalid npm cache limit" }
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_LIMIT_MIB, limitMiB)
            .putInt(KEY_DEFAULT_LIMIT_VERSION, DEFAULT_LIMIT_VERSION)
            .apply()
    }

    fun sizeBytes(context: Context): Long = directorySize(cacheDir(context))

    fun clear(context: Context): Boolean {
        val directory = cacheDir(context)
        directory.listFiles()?.forEach { child ->
            if (!deleteRecursively(child)) return false
        }
        return true
    }

    fun trimIfNeeded(context: Context): Map<String, Any> {
        val limitMiB = getLimitMiB(context)
        val beforeBytes = sizeBytes(context)
        val limitBytes = if (limitMiB == UNLIMITED) {
            Long.MAX_VALUE
        } else {
            limitMiB.toLong() * 1024L * 1024L
        }
        val trimmed = if (beforeBytes > limitBytes) {
            trimDirectory(cacheDir(context), limitBytes)
        } else {
            false
        }
        val afterBytes = if (trimmed) sizeBytes(context) else beforeBytes
        return mapOf(
            "limitMiB" to limitMiB,
            "beforeBytes" to beforeBytes,
            "afterBytes" to afterBytes,
            "cleared" to (trimmed && afterBytes == 0L),
            "trimmed" to trimmed,
        )
    }

    /**
     * Removes the oldest cache files until the requested limit is met.
     * npm treats missing or stale cacache entries as cache misses and fetches
     * them again, so gradual eviction is safe and preserves newer artifacts.
     */
    internal fun trimDirectory(directory: File, limitBytes: Long): Boolean {
        if (!directory.exists()) return false
        val files = directory.walkTopDown()
            .filter { it.isFile }
            .sortedBy { it.lastModified() }
            .toList()
        var currentBytes = files.sumOf { it.length() }
        if (currentBytes <= limitBytes) return false

        var changed = false
        for (file in files) {
            if (currentBytes <= limitBytes) break
            val length = file.length()
            if (file.delete()) {
                currentBytes -= length
                changed = true
            }
        }
        directory.walkBottomUp()
            .filter { it.isDirectory && it != directory }
            .forEach { child ->
                if (child.listFiles()?.isEmpty() == true) child.delete()
            }
        return changed
    }

    private fun directorySize(file: File): Long {
        if (!file.exists()) return 0L
        if (file.isFile) return file.length()
        return file.listFiles()?.sumOf { directorySize(it) } ?: 0L
    }

    private fun deleteRecursively(file: File): Boolean {
        if (file.isDirectory) {
            file.listFiles()?.forEach { child ->
                if (!deleteRecursively(child)) return false
            }
        }
        return !file.exists() || file.delete()
    }
}
