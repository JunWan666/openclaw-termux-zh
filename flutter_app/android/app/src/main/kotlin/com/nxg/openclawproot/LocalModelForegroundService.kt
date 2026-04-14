package com.junwan666.openclawzh

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import java.io.File
import java.io.InputStream
import java.net.InetSocketAddress
import java.net.Socket

class LocalModelForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "openclaw_local_model"
        const val NOTIFICATION_ID = 10
        const val EXTRA_BINARY_PATH = "binaryPath"
        const val EXTRA_MODEL_PATH = "modelPath"
        const val EXTRA_LOG_PATH = "logPath"
        const val EXTRA_PORT = "port"
        const val EXTRA_ALIAS = "alias"
        const val EXTRA_CONTEXT_SIZE = "contextSize"
        const val EXTRA_THREADS = "threads"
        const val EXTRA_THREADS_BATCH = "threadsBatch"
        const val EXTRA_BATCH_SIZE = "batchSize"
        const val EXTRA_UBATCH_SIZE = "ubatchSize"
        private const val RUNTIME_PID_HOST_RELATIVE_PATH =
            "rootfs/ubuntu/root/.openclaw/modules/llama.cpp/runtime/server.pid"

        var isRunning = false
            private set
        var currentPort = 18080
            private set

        private var instance: LocalModelForegroundService? = null
        @Volatile
        private var currentHostPid: Int = -1

        fun start(
            context: Context,
            binaryPath: String,
            modelPath: String,
            logPath: String,
            port: Int,
            alias: String,
            contextSize: Int,
            threads: Int,
            threadsBatch: Int,
            batchSize: Int,
            ubatchSize: Int,
        ) {
            val intent = Intent(context, LocalModelForegroundService::class.java).apply {
                putExtra(EXTRA_BINARY_PATH, binaryPath)
                putExtra(EXTRA_MODEL_PATH, modelPath)
                putExtra(EXTRA_LOG_PATH, logPath)
                putExtra(EXTRA_PORT, port)
                putExtra(EXTRA_ALIAS, alias)
                putExtra(EXTRA_CONTEXT_SIZE, contextSize)
                putExtra(EXTRA_THREADS, threads)
                putExtra(EXTRA_THREADS_BATCH, threadsBatch)
                putExtra(EXTRA_BATCH_SIZE, batchSize)
                putExtra(EXTRA_UBATCH_SIZE, ubatchSize)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, LocalModelForegroundService::class.java)
            context.stopService(intent)
        }

        fun updateStatus(text: String) {
            instance?.updateNotification(text)
        }

        fun snapshotRuntimeStats(context: Context): Map<String, Any>? {
            val hostPid = currentHostPid.takeIf { it > 0 }
            if (hostPid != null) {
                val hostStats = buildRuntimeStats(hostPid)
                if (hostStats != null) {
                    return hostStats
                }
            }

            val fallbackPid = readRuntimeRootPid(context)?.takeIf { it > 0 }
            if (fallbackPid != null && fallbackPid != hostPid) {
                val fallbackStats = buildRuntimeStats(fallbackPid)
                if (fallbackStats != null) {
                    return fallbackStats
                }
            }

            return null
        }

        private fun readRuntimeRootPid(context: Context): Int? {
            return try {
                File(context.filesDir, RUNTIME_PID_HOST_RELATIVE_PATH)
                    .takeIf { it.exists() && it.isFile }
                    ?.readText()
                    ?.trim()
                    ?.toIntOrNull()
                    ?.takeIf { it > 0 }
            } catch (_: Exception) {
                null
            }
        }

        private fun buildRuntimeStats(rootPid: Int): Map<String, Any>? {
            val statusByPid = scanProcessStatus()
            if (!statusByPid.containsKey(rootPid)) {
                return null
            }

            val processTree = collectProcessTree(rootPid, statusByPid)
            if (processTree.isEmpty()) {
                return null
            }

            var rssKiB = 0L
            var threadCount = 0
            var processTicks = 0L
            var sampledProcessCount = 0

            for (pid in processTree) {
                val status = statusByPid[pid] ?: continue
                val stat = readProcessStat(pid) ?: continue
                rssKiB += status.rssKiB
                threadCount += status.threadCount
                processTicks += stat.processTicks
                sampledProcessCount += 1
            }

            if (sampledProcessCount <= 0) {
                return null
            }

            val cpuTotalTicks = readCpuTotalTicks()

            return hashMapOf(
                "pid" to rootPid,
                "rssKiB" to rssKiB,
                "threadCount" to threadCount,
                "processTicks" to processTicks,
                "cpuTotalTicks" to cpuTotalTicks,
                "processCount" to sampledProcessCount,
            )
        }

        private fun collectProcessTree(
            rootPid: Int,
            statusByPid: Map<Int, HostProcessStatus>,
        ): Set<Int> {
            val byParent = HashMap<Int, MutableList<Int>>()
            for ((pid, status) in statusByPid) {
                byParent.getOrPut(status.parentPid) { mutableListOf() }.add(pid)
            }

            val visited = linkedSetOf<Int>()
            val queue = ArrayDeque<Int>()
            queue.add(rootPid)

            while (queue.isNotEmpty()) {
                val pid = queue.removeFirst()
                if (!visited.add(pid)) {
                    continue
                }
                for (childPid in byParent[pid].orEmpty()) {
                    if (!visited.contains(childPid)) {
                        queue.add(childPid)
                    }
                }
            }

            return visited
        }

        private fun scanProcessStatus(): Map<Int, HostProcessStatus> {
            val procDir = File("/proc")
            val results = HashMap<Int, HostProcessStatus>()
            val entries = procDir.listFiles() ?: return results
            for (entry in entries) {
                val pid = entry.name.toIntOrNull() ?: continue
                val status = readProcessStatus(pid) ?: continue
                results[pid] = status
            }
            return results
        }

        private fun readProcessStatus(pid: Int): HostProcessStatus? {
            return try {
                val lines = File("/proc/$pid/status").readLines()
                var parentPid = -1
                var rssKiB = 0L
                var threadCount = 0
                for (line in lines) {
                    when {
                        line.startsWith("PPid:") -> {
                            parentPid = line.substringAfter(':').trim().toIntOrNull() ?: -1
                        }
                        line.startsWith("VmRSS:") -> {
                            rssKiB = line.substringAfter(':')
                                .trim()
                                .split(Regex("\\s+"))
                                .firstOrNull()
                                ?.toLongOrNull() ?: 0L
                        }
                        line.startsWith("Threads:") -> {
                            threadCount = line.substringAfter(':').trim().toIntOrNull() ?: 0
                        }
                    }
                }
                HostProcessStatus(
                    parentPid = parentPid,
                    rssKiB = rssKiB,
                    threadCount = threadCount,
                )
            } catch (_: Exception) {
                null
            }
        }

        private fun readProcessStat(pid: Int): HostProcessStat? {
            return try {
                val raw = File("/proc/$pid/stat").readText().trim()
                val closeParen = raw.lastIndexOf(')')
                if (closeParen <= 0 || closeParen + 2 >= raw.length) {
                    return null
                }
                val fields = raw.substring(closeParen + 2).trim().split(Regex("\\s+"))
                if (fields.size < 13) {
                    return null
                }
                val utime = fields[11].toLongOrNull() ?: return null
                val stime = fields[12].toLongOrNull() ?: return null
                HostProcessStat(processTicks = utime + stime)
            } catch (_: Exception) {
                null
            }
        }

        private fun readCpuTotalTicks(): Long {
            return try {
                val cpuLine = File("/proc/stat").useLines { lines ->
                    lines.firstOrNull { it.startsWith("cpu ") }
                } ?: return 0L
                cpuLine
                    .trim()
                    .split(Regex("\\s+"))
                    .drop(1)
                    .sumOf { it.toLongOrNull() ?: 0L }
            } catch (_: Exception) {
                0L
            }
        }
    }

    private var modelShellProcess: Process? = null
    private var shellOutputThread: Thread? = null
    private var shellErrorThread: Thread? = null
    private var workerThread: Thread? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val binaryPath = intent?.getStringExtra(EXTRA_BINARY_PATH).orEmpty()
        val modelPath = intent?.getStringExtra(EXTRA_MODEL_PATH).orEmpty()
        val logPath = intent?.getStringExtra(EXTRA_LOG_PATH).orEmpty()
        val port = intent?.getIntExtra(EXTRA_PORT, 18080) ?: 18080
        val alias = intent?.getStringExtra(EXTRA_ALIAS).orEmpty()
        val contextSize = intent?.getIntExtra(EXTRA_CONTEXT_SIZE, 4096) ?: 4096
        val threads = intent?.getIntExtra(EXTRA_THREADS, 4) ?: 4
        val threadsBatch = intent?.getIntExtra(EXTRA_THREADS_BATCH, threads) ?: threads
        val batchSize = intent?.getIntExtra(EXTRA_BATCH_SIZE, 512) ?: 512
        val ubatchSize = intent?.getIntExtra(EXTRA_UBATCH_SIZE, minOf(batchSize, 256))
            ?: minOf(batchSize, 256)

        currentPort = port
        startForeground(
            NOTIFICATION_ID,
            buildNotification("Starting local model on port $port")
        )

        if (binaryPath.isBlank() || modelPath.isBlank() || logPath.isBlank()) {
            updateNotification("local model start failed: missing binary, model, or log path")
            stopSelf()
            return START_NOT_STICKY
        }

        if (workerThread?.isAlive == true || modelShellProcess?.isAlive == true) {
            stopModelShell()
            workerThread?.interrupt()
            workerThread = null
        }

        acquireWakeLock()
        startModelProcess(
            binaryPath = binaryPath,
            modelPath = modelPath,
            logPath = logPath,
            port = port,
            alias = alias,
            contextSize = contextSize,
            threads = threads,
            threadsBatch = threadsBatch,
            batchSize = batchSize,
            ubatchSize = ubatchSize,
        )
        return START_REDELIVER_INTENT
    }

    override fun onDestroy() {
        isRunning = false
        currentPort = 18080
        currentHostPid = -1
        instance = null
        workerThread?.interrupt()
        workerThread = null
        stopModelShell()
        clearRuntimePidFile()
        releaseWakeLock()
        super.onDestroy()
    }

    private fun startModelProcess(
        binaryPath: String,
        modelPath: String,
        logPath: String,
        port: Int,
        alias: String,
        contextSize: Int,
        threads: Int,
        threadsBatch: Int,
        batchSize: Int,
        ubatchSize: Int,
    ) {
        if (workerThread?.isAlive == true || modelShellProcess?.isAlive == true) return

        isRunning = true
        instance = this

        workerThread = Thread {
            val filesDir = applicationContext.filesDir.absolutePath
            val nativeLibDir = applicationContext.applicationInfo.nativeLibraryDir
            val processManager = ProcessManager(filesDir, nativeLibDir)
            val bootstrapManager = BootstrapManager(applicationContext, filesDir, nativeLibDir)

            var restartCount = 0
            val maxRestarts = 1

            while (isRunning && restartCount <= maxRestarts) {
                try {
                    try {
                        bootstrapManager.setupDirectories()
                    } catch (_: Exception) {
                    }
                    try {
                        bootstrapManager.writeResolvConf()
                    } catch (_: Exception) {
                    }

                    val shell = processManager.startProotProcess(
                        buildServerCommand(
                            binaryPath = binaryPath,
                            modelPath = modelPath,
                            logPath = logPath,
                            port = port,
                            alias = alias,
                            contextSize = contextSize,
                            threads = threads,
                            threadsBatch = threadsBatch,
                            batchSize = batchSize,
                            ubatchSize = ubatchSize,
                        )
                    )

                    modelShellProcess = shell
                    currentHostPid = resolveProcessPid(shell) ?: -1
                    shellOutputThread = drainStream(shell.inputStream, "LocalModelOut")
                    shellErrorThread = drainStream(shell.errorStream, "LocalModelErr")

                    val started = waitForStarted(port, 45000L)
                    if (started) {
                        restartCount = 0
                        updateNotification("Local model running on port $port")
                    } else {
                        updateNotification("Local model failed to open port $port")
                    }

                    shell.waitFor()
                } catch (_: InterruptedException) {
                    break
                } catch (e: Exception) {
                    updateNotification(
                        "local model error: ${e.message?.take(60) ?: "unknown"}"
                    )
                } finally {
                    stopModelShell()
                    terminateResidualProcesses()
                    clearRuntimePidFile()
                }

                if (!isRunning) {
                    break
                }

                if (restartCount < maxRestarts) {
                    restartCount++
                    updateNotification("Local model exited, restarting ($restartCount/$maxRestarts)")
                    try {
                        Thread.sleep(2000L * restartCount)
                    } catch (_: InterruptedException) {
                        break
                    }
                } else {
                    isRunning = false
                    updateNotification("Local model failed to stay alive")
                    stopSelf()
                }
            }
        }.apply {
            name = "LocalModelForegroundWorker"
            start()
        }
    }

    private fun buildServerCommand(
        binaryPath: String,
        modelPath: String,
        logPath: String,
        port: Int,
        alias: String,
        contextSize: Int,
        threads: Int,
        threadsBatch: Int,
        batchSize: Int,
        ubatchSize: Int,
    ): String {
        return listOf(
            "mkdir -p ${shellQuote("/root/.openclaw/modules/llama.cpp/logs")} ${shellQuote("/root/.openclaw/modules/llama.cpp/runtime")} ${shellQuote("/root/.cache/llama.cpp")}",
            "touch ${shellQuote(logPath)}",
            "printf '%s\\n' \"\$\$\" > ${shellQuote("/root/.openclaw/modules/llama.cpp/runtime/server.pid")}",
            "printf '[%s] starting model=%s alias=%s port=%s context=%s threads=%s threads_batch=%s batch=%s ubatch=%s\\n' \"\$(date -Iseconds 2>/dev/null || date)\" ${shellQuote(modelPath)} ${shellQuote(alias)} \"$port\" \"$contextSize\" \"$threads\" \"$threadsBatch\" \"$batchSize\" \"$ubatchSize\" >> ${shellQuote(logPath)}",
            "exec ${shellQuote(binaryPath)} -m ${shellQuote(modelPath)} -a ${shellQuote(alias)} --host 0.0.0.0 --port $port -c $contextSize -t $threads -tb $threadsBatch -b $batchSize -ub $ubatchSize >> ${shellQuote(logPath)} 2>&1",
        ).joinToString("\n")
    }

    private fun stopModelShell() {
        modelShellProcess?.let {
            try {
                it.destroy()
            } catch (_: Exception) {
            }
            try {
                it.destroyForcibly()
            } catch (_: Exception) {
            }
        }
        modelShellProcess = null
        currentHostPid = -1

        shellOutputThread?.interrupt()
        shellOutputThread = null
        shellErrorThread?.interrupt()
        shellErrorThread = null
    }

    private fun drainStream(input: InputStream, threadName: String): Thread {
        return Thread {
            val buffer = ByteArray(4096)
            try {
                while (!Thread.currentThread().isInterrupted) {
                    val count = input.read(buffer)
                    if (count <= 0) break
                }
            } catch (_: Exception) {
            }
        }.apply {
            name = threadName
            isDaemon = true
            start()
        }
    }

    private fun resolveProcessPid(process: Process): Int? {
        return try {
            val pidMethod = Process::class.java.getMethod("pid")
            val value = pidMethod.invoke(process)
            when (value) {
                is Long -> value.toInt()
                is Int -> value
                else -> null
            }?.takeIf { it > 0 }
        } catch (_: Exception) {
            null
        }
    }

    private fun waitForStarted(port: Int, timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (isRunning && System.currentTimeMillis() < deadline) {
            if (isPortOpen(port)) {
                return true
            }
            Thread.sleep(800)
        }
        return false
    }

    private fun isPortOpen(port: Int): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress("127.0.0.1", port), 1500)
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun terminateResidualProcesses() {
        try {
            val filesDir = applicationContext.filesDir.absolutePath
            val nativeLibDir = applicationContext.applicationInfo.nativeLibraryDir
            val processManager = ProcessManager(filesDir, nativeLibDir)
            processManager.runInProotSync(
                listOf(
                    "current_pid=\"\$\$\"",
                    "parent_pid=\"\$PPID\"",
                    "for proc_dir in /proc/[0-9]*; do",
                    "  pid=\"\${proc_dir##*/}\"",
                    "  [ \"\$pid\" = \"\$current_pid\" ] && continue",
                    "  [ \"\$pid\" = \"\$parent_pid\" ] && continue",
                    "  [ -r \"\$proc_dir/comm\" ] || continue",
                    "  if [ \"\$(cat \"\$proc_dir/comm\" 2>/dev/null || true)\" = \"llama-server\" ]; then",
                    "    kill \"\$pid\" 2>/dev/null || true",
                    "  fi",
                    "done",
                ).joinToString("\n"),
                8,
            )
        } catch (_: Exception) {
        }
    }

    private fun clearRuntimePidFile() {
        try {
            File(applicationContext.filesDir, RUNTIME_PID_HOST_RELATIVE_PATH).delete()
        } catch (_: Exception) {
        }
    }

    private fun acquireWakeLock() {
        releaseWakeLock()
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "OpenClaw::LocalModelWakeLock"
        )
        wakeLock?.acquire(24 * 60 * 60 * 1000L)
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
        wakeLock = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "OpenClaw Local Model",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps the local llama.cpp model running in the background"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder.setContentTitle("Local Model")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(pendingIntent)
            .setOngoing(true)

        return builder.build()
    }

    private fun updateNotification(text: String) {
        try {
            val manager = getSystemService(NotificationManager::class.java)
            manager.notify(NOTIFICATION_ID, buildNotification(text))
        } catch (_: Exception) {
        }
    }

    private fun shellQuote(value: String): String {
        return "'${value.replace("'", "'\\''")}'"
    }
}

private data class HostProcessStatus(
    val parentPid: Int,
    val rssKiB: Long,
    val threadCount: Int,
)

private data class HostProcessStat(
    val processTicks: Long,
)
