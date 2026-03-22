package com.junwan666.openclawzh

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import io.flutter.plugin.common.EventChannel
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.net.InetSocketAddress
import java.net.Socket
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

class GatewayService : Service() {
    companion object {
        const val CHANNEL_ID = "openclaw_gateway"
        const val NOTIFICATION_ID = 1
        var isRunning = false
            private set
        var logSink: EventChannel.EventSink? = null
        private var instance: GatewayService? = null
        private val mainHandler = Handler(Looper.getMainLooper())

        /** Check if the gateway process is actually alive (not just the flag).
         *  Safe to call from the main thread 鈥?no blocking I/O. */
        fun isProcessAlive(): Boolean {
            val inst = instance ?: return false
            if (inst.stopping) return false
            if (!isRunning) return false
            val proc = inst.gatewayProcess
            // If we have a process reference, check if it's actually alive
            if (proc != null) return proc.isAlive
            // No process ref yet 鈥?still in setup phase.
            // If the gateway thread is alive, setup is ongoing 鈥?report true.
            // This covers slow devices where dir setup takes a long time.
            val thread = inst.gatewayThread
            if (thread != null && thread.isAlive) return true
            // Fallback: within startup window (120s)
            val elapsed = System.currentTimeMillis() - inst.startTime
            return elapsed < 120_000
        }

        fun start(context: Context) {
            val intent = Intent(context, GatewayService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, GatewayService::class.java)
            context.stopService(intent)
        }

        fun stopAndWait(context: Context, timeoutMs: Long = 15_000L): Boolean {
            val existing = instance
            existing?.requestStop("user")
            stop(context)

            val deadline = System.currentTimeMillis() + timeoutMs
            while (System.currentTimeMillis() < deadline) {
                val service = instance ?: existing
                if (service == null || service.isShutdownComplete()) {
                    return true
                }
                try {
                    Thread.sleep(200)
                } catch (_: InterruptedException) {
                    break
                }
            }

            (instance ?: existing)?.requestStop("force-cleanup")
            return (instance ?: existing)?.isShutdownComplete() ?: true
        }
    }

    private var gatewayProcess: Process? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var restartCount = 0
    private val maxRestarts = 5
    private var startTime: Long = 0
    private var processStartTime: Long = 0
    private var uptimeThread: Thread? = null
    private var watchdogThread: Thread? = null
    private var gatewayThread: Thread? = null
    private val lock = Object()
    @Volatile private var stopping = false
    private val ansiRegex = Regex("\\u001B\\[[0-9;]*[A-Za-z]")
    private val leadingTimestampRegex = Regex("^(\\d{4}-\\d{2}-\\d{2}T\\S+)\\s+(.*)$")
    private val logTimeFormatter =
        DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").withZone(ZoneId.systemDefault())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification("Starting..."))
        if (isRunning) {
            updateNotificationRunning()
            return START_STICKY
        }
        stopping = false
        acquireWakeLock()
        startGateway()
        return START_STICKY
    }

    override fun onDestroy() {
        requestStop("service-destroyed", waitForShutdown = false)
        releaseWakeLock()
        isRunning = false
        instance = null
        super.onDestroy()
    }

    /** Check if gateway port is already in use (another instance running). */
    private fun isPortInUse(port: Int = 18789): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress("127.0.0.1", port), 1000)
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun startGateway() {
        synchronized(lock) {
            if (stopping) return
            if (gatewayProcess?.isAlive == true) return

            isRunning = true
            instance = this
            startTime = System.currentTimeMillis()
        }

        gatewayThread = Thread {
            try {
                // Check if an existing gateway is already listening on the port.
                // Moved inside thread to avoid blocking the main thread (#60).
                if (isPortInUse()) {
                    emitLog("[INFO] Gateway already running on port 18789, adopting existing instance")
                    updateNotificationRunning()
                    startUptimeTicker()
                    startWatchdog()
                    return@Thread
                }

                emitLog("[INFO] Setting up environment...")
                val filesDir = applicationContext.filesDir.absolutePath
                val nativeLibDir = applicationContext.applicationInfo.nativeLibraryDir
                val pm = ProcessManager(filesDir, nativeLibDir)

                // Recreate all directories (config, tmp, home, lib, proc/sys fakes)
                // in case Android cleared them after an app update (#40).
                // This must run before proot 鈥?it needs bind-mount targets.
                val bootstrapManager = BootstrapManager(applicationContext, filesDir, nativeLibDir)
                try {
                    bootstrapManager.setupDirectories()
                    emitLog("[INFO] Directories ready")
                } catch (e: Exception) {
                    emitLog("[WARN] setupDirectories failed: ${e.message}")
                }
                try {
                    bootstrapManager.writeResolvConf()
                } catch (e: Exception) {
                    emitLog("[WARN] writeResolvConf failed: ${e.message}")
                }

                // Last-resort: verify resolv.conf exists, create inline if not
                val resolvContent = "nameserver 8.8.8.8\nnameserver 8.8.4.4\n"
                try {
                    val resolvFile = File(filesDir, "config/resolv.conf")
                    if (!resolvFile.exists() || resolvFile.length() == 0L) {
                        resolvFile.parentFile?.mkdirs()
                        resolvFile.writeText(resolvContent)
                        emitLog("[INFO] resolv.conf created (inline fallback)")
                    }
                } catch (e: Exception) {
                    emitLog("[WARN] inline resolv.conf fallback failed: ${e.message}")
                }
                // Also write into rootfs /etc/ so DNS works even if bind-mount fails
                try {
                    val rootfsResolv = File(filesDir, "rootfs/ubuntu/etc/resolv.conf")
                    if (!rootfsResolv.exists() || rootfsResolv.length() == 0L) {
                        rootfsResolv.parentFile?.mkdirs()
                        rootfsResolv.writeText(resolvContent)
                    }
                } catch (_: Exception) {}

                // Abort if stop was requested during setup
                if (stopping) return@Thread

                // Final check right before launch 鈥?another instance may have
                // started between the first check and now
                if (isPortInUse()) {
                    emitLog("Gateway already running on port 18789, skipping launch")
                    updateNotificationRunning()
                    startUptimeTicker()
                    startWatchdog()
                    return@Thread
                }

                emitLog("[INFO] Spawning proot process...")
                synchronized(lock) {
                    if (stopping) return@Thread
                    processStartTime = System.currentTimeMillis()
                    gatewayProcess = pm.startProotProcess("openclaw gateway --verbose")
                }
                updateNotificationRunning()
                emitLog("[INFO] Gateway process spawned")
                startUptimeTicker()
                startWatchdog()

                // Read stdout
                val proc = gatewayProcess!!
                val stdoutReader = BufferedReader(InputStreamReader(proc.inputStream))
                Thread {
                    try {
                        var line: String?
                        while (stdoutReader.readLine().also { line = it } != null) {
                            val l = line ?: continue
                            emitLog(l)
                        }
                    } catch (_: Exception) {}
                }.start()

                // Read stderr 鈥?log all lines on first attempt for debugging visibility
                val stderrReader = BufferedReader(InputStreamReader(proc.errorStream))
                val currentRestartCount = restartCount
                Thread {
                    try {
                        var line: String?
                        while (stderrReader.readLine().also { line = it } != null) {
                            val l = line ?: continue
                            if (isBenignStdioSanitizeWarning(l)) {
                                continue
                            }
                            if (currentRestartCount == 0 ||
                                (!l.contains("proot warning") && !l.contains("can't sanitize"))) {
                                emitLog("[ERR] $l")
                            }
                        }
                    } catch (_: Exception) {}
                }.start()

                val exitCode = proc.waitFor()
                val uptimeMs = System.currentTimeMillis() - processStartTime
                val uptimeSec = uptimeMs / 1000
                emitLog("[INFO] Gateway exited with code $exitCode (uptime: ${uptimeSec}s)")

                // If stop was requested, don't auto-restart
                if (stopping) return@Thread

                // If the gateway ran for >60s, it was a transient crash 鈥?reset counter
                if (uptimeMs > 60_000) {
                    restartCount = 0
                }

                if (isRunning && restartCount < maxRestarts) {
                    restartCount++
                    // Cap delay at 16s to avoid excessively long waits
                    val delayMs = minOf(2000L * (1 shl (restartCount - 1)), 16000L)
                    emitLog("[INFO] Auto-restarting in ${delayMs / 1000}s (attempt $restartCount/$maxRestarts)...")
                    updateNotification("Restarting in ${delayMs / 1000}s (attempt $restartCount)...")
                    Thread.sleep(delayMs)
                    if (!stopping) {
                        startTime = System.currentTimeMillis()
                        startGateway()
                    }
                } else if (restartCount >= maxRestarts) {
                    emitLog("[WARN] Max restarts reached. Gateway stopped.")
                    updateNotification("Gateway stopped (crashed)")
                    isRunning = false
                }
            } catch (e: Exception) {
                if (!stopping) {
                    emitLog("[ERROR] Gateway error: ${e.message}")
                    isRunning = false
                    updateNotification("Gateway error")
                }
            }
        }.also { it.start() }
    }

    private fun requestStop(reason: String, waitForShutdown: Boolean = true) {
        synchronized(lock) {
            if (stopping) {
                return
            }
            stopping = true
            isRunning = false
            restartCount = maxRestarts // Prevent auto-restart
            uptimeThread?.interrupt()
            uptimeThread = null
            watchdogThread?.interrupt()
            watchdogThread = null
            gatewayThread?.interrupt()
        }

        updateNotification("Stopping...")
        emitLog("[INFO] Stopping gateway...")

        val runningProcess = synchronized(lock) { gatewayProcess }
        try {
            runningProcess?.destroy()
        } catch (_: Exception) {}
        try {
            runningProcess?.destroyForcibly()
        } catch (_: Exception) {}

        forceCleanupResidualGatewayProcesses()
        if (waitForShutdown) {
            waitForShutdown()
        }

        synchronized(lock) {
            gatewayProcess = null
            gatewayThread = null
            startTime = 0
            processStartTime = 0
        }

        emitLog("[INFO] Gateway stopped by $reason")
        updateNotification("Gateway stopped")
    }

    private fun isShutdownComplete(): Boolean {
        val processAlive = synchronized(lock) { gatewayProcess?.isAlive == true }
        if (processAlive) {
            return false
        }
        if (gatewayThread?.isAlive == true) {
            return false
        }
        return !isPortInUse()
    }

    private fun waitForShutdown(timeoutMs: Long = 10_000L) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (isShutdownComplete()) {
                return
            }
            try {
                Thread.sleep(200)
            } catch (_: InterruptedException) {
                return
            }
        }
    }

    private fun forceCleanupResidualGatewayProcesses() {
        val patterns = listOf(
            "openclaw gateway --verbose",
            "openclaw.mjs gateway",
            "node-wrapper.js",
        )

        for (pattern in patterns) {
            try {
                val escaped = pattern.replace("'", "'\"'\"'")
                ProcessBuilder(
                    "/system/bin/sh",
                    "-c",
                    "ps -A | grep -F '$escaped' | grep -v grep | while read -r line; do pid=\$(echo \"\$line\" | awk '{print \$2}'); kill -9 \"\$pid\" 2>/dev/null; done"
                ).start().waitFor()
            } catch (_: Exception) {}
        }
    }

    /** Watchdog: periodically checks if the proot process is alive.
     *  If the process dies and the waitFor() thread hasn't noticed yet,
     *  this ensures isRunning is updated promptly. */
    private fun startWatchdog() {
        watchdogThread?.interrupt()
        watchdogThread = Thread {
            try {
                // Wait 45s before first check 鈥?give the process time to start
                Thread.sleep(45_000)
                while (!Thread.interrupted() && isRunning && !stopping) {
                    val proc = gatewayProcess
                    if (proc != null && !proc.isAlive) {
                        // Process died 鈥?the waitFor() thread should handle restart,
                        // but update the flag in case it's stuck
                        emitLog("[WARN] Watchdog: gateway process not alive")
                        break
                    }
                    // Also check if port is still responding after initial startup
                    if (proc != null && !isPortInUse()) {
                        emitLog("[WARN] Watchdog: port 18789 not responding")
                    }
                    Thread.sleep(15_000) // Check every 15s
                }
            } catch (_: InterruptedException) {}
        }.apply { isDaemon = true; start() }
    }

    private fun startUptimeTicker() {
        uptimeThread?.interrupt()
        uptimeThread = Thread {
            try {
                while (!Thread.interrupted() && isRunning) {
                    Thread.sleep(60_000) // Update every minute
                    if (isRunning) {
                        updateNotificationRunning()
                    }
                }
            } catch (_: InterruptedException) {}
        }.apply { isDaemon = true; start() }
    }

    private fun formatUptime(): String {
        val elapsed = System.currentTimeMillis() - startTime
        val seconds = elapsed / 1000
        val minutes = seconds / 60
        val hours = minutes / 60
        return when {
            hours > 0 -> "${hours}h ${minutes % 60}m"
            minutes > 0 -> "${minutes}m"
            else -> "${seconds}s"
        }
    }

    private fun updateNotificationRunning() {
        updateNotification("Running on port 18789 \u2022 ${formatUptime()}")
    }

    /** Emit a log message to the Flutter EventChannel.
     *  MUST post to main thread 鈥?EventSink.success() is not thread-safe. */
    private fun emitLog(message: String) {
        try {
            val formatted = normalizeLogLine(message)
            if (formatted.isBlank()) return
            mainHandler.post {
                try {
                    logSink?.success(formatted)
                } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
    }

    private fun isBenignStdioSanitizeWarning(message: String): Boolean {
        return message.contains("proot warning") &&
            (message.contains("can't sanitize binding \"/proc/self/fd/0\"") ||
                message.contains("can't sanitize binding \"/proc/self/fd/1\"") ||
                message.contains("can't sanitize binding \"/proc/self/fd/2\""))
    }

    private fun normalizeLogLine(message: String): String {
        val cleaned = ansiRegex.replace(message, "").trim()
        if (cleaned.isEmpty()) return ""

        val match = leadingTimestampRegex.find(cleaned)
        if (match != null) {
            val parsed = formatTimestamp(match.groupValues[1])
            if (parsed != null) {
                return "$parsed ${match.groupValues[2]}".trim()
            }
        }

        return "${logTimeFormatter.format(Instant.now())} $cleaned"
    }

    private fun formatTimestamp(raw: String): String? {
        val instant = runCatching { Instant.parse(raw) }.getOrNull()
            ?: runCatching { OffsetDateTime.parse(raw).toInstant() }.getOrNull()
            ?: runCatching {
                LocalDateTime.parse(raw).atZone(ZoneId.systemDefault()).toInstant()
            }.getOrNull()

        return instant?.let { logTimeFormatter.format(it) }
    }

    private fun acquireWakeLock() {
        releaseWakeLock()
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "OpenClaw::GatewayWakeLock"
        )
        wakeLock?.acquire(24 * 60 * 60 * 1000L) // 24 hours max
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "OpenClaw Gateway",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps the OpenClaw gateway running in the background"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder.setContentTitle("OpenClaw Gateway")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(pendingIntent)
            .setOngoing(true)

        // Show elapsed time chronometer when running
        if (isRunning && startTime > 0) {
            builder.setWhen(startTime)
            builder.setShowWhen(true)
            builder.setUsesChronometer(true)
        }

        return builder.build()
    }

    private fun updateNotification(text: String) {
        try {
            val manager = getSystemService(NotificationManager::class.java)
            manager.notify(NOTIFICATION_ID, buildNotification(text))
        } catch (_: Exception) {}
    }
}

