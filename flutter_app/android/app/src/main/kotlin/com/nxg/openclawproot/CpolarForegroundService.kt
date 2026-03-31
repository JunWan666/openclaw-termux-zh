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
import java.io.InputStream
import java.net.InetSocketAddress
import java.net.Socket

class CpolarForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "openclaw_cpolar"
        const val NOTIFICATION_ID = 9
        const val EXTRA_BINARY_PATH = "binaryPath"
        const val EXTRA_CONFIG_PATH = "configPath"
        const val EXTRA_LOG_PATH = "logPath"
        const val EXTRA_WEB_PORT = "webPort"

        var isRunning = false
            private set
        var currentWebPort = 9200
            private set

        private var instance: CpolarForegroundService? = null

        fun start(
            context: Context,
            binaryPath: String,
            configPath: String,
            logPath: String,
            webPort: Int
        ) {
            val intent = Intent(context, CpolarForegroundService::class.java).apply {
                putExtra(EXTRA_BINARY_PATH, binaryPath)
                putExtra(EXTRA_CONFIG_PATH, configPath)
                putExtra(EXTRA_LOG_PATH, logPath)
                putExtra(EXTRA_WEB_PORT, webPort)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, CpolarForegroundService::class.java)
            context.stopService(intent)
        }

        fun updateStatus(text: String) {
            instance?.updateNotification(text)
        }
    }

    private var cpolarShellProcess: Process? = null
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
        val configPath = intent?.getStringExtra(EXTRA_CONFIG_PATH).orEmpty()
        val logPath = intent?.getStringExtra(EXTRA_LOG_PATH).orEmpty()
        val webPort = intent?.getIntExtra(EXTRA_WEB_PORT, 9200) ?: 9200

        currentWebPort = webPort
        startForeground(
            NOTIFICATION_ID,
            buildNotification("Starting cpolar on port $webPort")
        )

        if (isRunning) {
            updateNotification("cpolar supervisor already running on port $webPort")
            return START_REDELIVER_INTENT
        }

        if (binaryPath.isBlank() || configPath.isBlank() || logPath.isBlank()) {
            updateNotification("cpolar start failed: missing binary, config, or log path")
            stopSelf()
            return START_NOT_STICKY
        }

        acquireWakeLock()
        startCpolarProcess(
            binaryPath = binaryPath,
            configPath = configPath,
            logPath = logPath,
            webPort = webPort
        )
        return START_REDELIVER_INTENT
    }

    override fun onDestroy() {
        isRunning = false
        currentWebPort = 9200
        instance = null
        workerThread?.interrupt()
        workerThread = null
        stopCpolarShell()
        releaseWakeLock()
        super.onDestroy()
    }

    private fun startCpolarProcess(
        binaryPath: String,
        configPath: String,
        logPath: String,
        webPort: Int
    ) {
        if (workerThread?.isAlive == true || cpolarShellProcess?.isAlive == true) return

        isRunning = true
        instance = this

        workerThread = Thread {
            val filesDir = applicationContext.filesDir.absolutePath
            val nativeLibDir = applicationContext.applicationInfo.nativeLibraryDir
            val processManager = ProcessManager(filesDir, nativeLibDir)
            val bootstrapManager =
                BootstrapManager(applicationContext, filesDir, nativeLibDir)

            var restartCount = 0
            val maxRestarts = 2

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
                        buildSupervisorCommand(
                            binaryPath = binaryPath,
                            configPath = configPath,
                            logPath = logPath,
                            webPort = webPort
                        )
                    )

                    cpolarShellProcess = shell
                    shellOutputThread = drainStream(shell.inputStream, "CpolarSupervisorOut")
                    shellErrorThread = drainStream(shell.errorStream, "CpolarSupervisorErr")

                    updateNotification("Starting cpolar with nohup start-all")

                    val started = waitForStarted(processManager, webPort, 45000L)
                    if (!started) {
                        runDiagnostics(
                            processManager = processManager,
                            binaryPath = binaryPath,
                            configPath = configPath,
                            logPath = logPath
                        )
                    }

                    if (started || waitForStarted(processManager, webPort, 8000L)) {
                        restartCount = 0
                        updateNotification(buildRunningStatus(processManager, webPort))

                        while (isRunning && shell.isAlive) {
                            if (!isCpolarAvailable(processManager, webPort)) {
                                updateNotification("cpolar supervisor is retrying nohup start-all")
                            }
                            Thread.sleep(5000)
                        }
                    } else {
                        updateNotification("cpolar failed to stay alive, check access.log")
                    }
                } catch (_: InterruptedException) {
                    break
                } catch (e: Exception) {
                    updateNotification(
                        "cpolar supervisor error: ${e.message?.take(60) ?: "unknown"}"
                    )
                } finally {
                    stopCpolarShell()
                }

                if (!isRunning) {
                    break
                }

                if (restartCount < maxRestarts) {
                    restartCount++
                    updateNotification(
                        "cpolar supervisor exited, restarting (${restartCount}/${maxRestarts})"
                    )
                    try {
                        Thread.sleep(2000L * restartCount)
                    } catch (_: InterruptedException) {
                        break
                    }
                } else {
                    isRunning = false
                    updateNotification("cpolar failed to stay alive, check access.log")
                    stopSelf()
                }
            }
        }.apply {
            name = "CpolarForegroundWorker"
            start()
        }
    }

    private fun buildSupervisorCommand(
        binaryPath: String,
        configPath: String,
        logPath: String,
        webPort: Int
    ): String {
        val escapedBinaryPath = shellQuote(binaryPath)
        val escapedConfigPath = shellQuote(configPath)
        val escapedLogPath = shellQuote(logPath)
        return """
            mkdir -p ${shellQuote("/usr/local/etc/cpolar")} ${shellQuote("/var/log/cpolar")}
            touch '$escapedLogPath'
            log_line() {
              printf '[%s] %s\n' "${'$'}(date -Iseconds 2>/dev/null || date)" "${'$'}1" >> '$escapedLogPath'
            }
            has_cpolar_process() {
              for proc_dir in /proc/[0-9]*; do
                [ -r "${'$'}proc_dir/comm" ] || continue
                if [ "$(cat "${'$'}proc_dir/comm" 2>/dev/null || true)" = "cpolar" ]; then
                  return 0
                fi
              done
              return 1
            }
            launch_cpolar() {
              log_line "cpolar start request, target dashboard port: $webPort"
              log_line "expected installed binary: $binaryPath"
              log_line "direct command: nohup cpolar start-all -daemon=on -dashboard=on -config=$configPath -log=$logPath > /dev/null 2>&1 &"
              nohup cpolar start-all -daemon=on -dashboard=on -config='$escapedConfigPath' -log='$escapedLogPath' > /dev/null 2>&1 &
              log_line "nohup submitted, shell pid=${'$'}!"
            }
            log_line "cpolar supervisor started"
            command -v cpolar >> '$escapedLogPath' 2>&1 || true
            '$escapedBinaryPath' version >> '$escapedLogPath' 2>&1 || true
            if ! has_cpolar_process; then
              launch_cpolar
            fi
            while true; do
              if ! has_cpolar_process; then
                log_line "cpolar process missing, relaunching nohup start-all"
                launch_cpolar
                sleep 3
              fi
              sleep 5
            done
        """.trimIndent()
    }

    private fun runDiagnostics(
        processManager: ProcessManager,
        binaryPath: String,
        configPath: String,
        logPath: String
    ) {
        try {
            processManager.runInProotSync(
                buildDiagnosticCommand(
                    binaryPath = binaryPath,
                    configPath = configPath,
                    logPath = logPath
                ),
                10
            )
        } catch (_: Exception) {
        }
    }

    private fun buildDiagnosticCommand(
        binaryPath: String,
        configPath: String,
        logPath: String
    ): String {
        val escapedBinaryPath = shellQuote(binaryPath)
        val escapedConfigPath = shellQuote(configPath)
        val escapedLogPath = shellQuote(logPath)
        return """
            printf '[%s] start check timed out, collecting diagnostics only\n' "${'$'}(date -Iseconds 2>/dev/null || date)" >> '$escapedLogPath'
            command -v cpolar >> '$escapedLogPath' 2>&1 || true
            '$escapedBinaryPath' version >> '$escapedLogPath' 2>&1 || true
            ls -l '$escapedBinaryPath' >> '$escapedLogPath' 2>&1 || true
            if [ -f '$escapedConfigPath' ]; then
              echo '---- cpolar config begin ----' >> '$escapedLogPath'
              sed -n '1,120p' '$escapedConfigPath' >> '$escapedLogPath' 2>&1 || true
              echo '---- cpolar config end ----' >> '$escapedLogPath'
            fi
            ps -ef | grep '[c]polar' >> '$escapedLogPath' 2>&1 || true
        """.trimIndent()
    }

    private fun stopCpolarShell() {
        cpolarShellProcess?.let {
            try {
                it.destroy()
            } catch (_: Exception) {
            }
            try {
                it.destroyForcibly()
            } catch (_: Exception) {
            }
        }
        cpolarShellProcess = null

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

    private fun waitForStarted(
        processManager: ProcessManager,
        port: Int,
        timeoutMs: Long
    ): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (isRunning && System.currentTimeMillis() < deadline) {
            if (isCpolarAvailable(processManager, port)) {
                return true
            }
            Thread.sleep(800)
        }
        return false
    }

    private fun isCpolarAvailable(processManager: ProcessManager, port: Int): Boolean {
        return hasCpolarProcess(processManager) || isEndpointActive(port)
    }

    private fun hasCpolarProcess(processManager: ProcessManager): Boolean {
        return try {
            val output = processManager.runInProotSync(
                """
                    found=0
                    for proc_dir in /proc/[0-9]*; do
                      [ -r "${'$'}proc_dir/comm" ] || continue
                      if [ "$(cat "${'$'}proc_dir/comm" 2>/dev/null || true)" = "cpolar" ]; then
                        found=1
                        break
                      fi
                    done
                    if [ "${'$'}found" -eq 1 ]; then
                      echo running
                    fi
                """.trimIndent(),
                5
            )
            output.contains("running")
        } catch (_: Exception) {
            false
        }
    }

    private fun buildRunningStatus(processManager: ProcessManager, port: Int): String {
        return when {
            isEndpointActive(port) -> "cpolar running on port $port"
            hasCpolarProcess(processManager) -> "cpolar process started, dashboard warming up"
            else -> "cpolar start requested"
        }
    }

    private fun isEndpointActive(port: Int): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress("127.0.0.1", port), 1500)
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun acquireWakeLock() {
        releaseWakeLock()
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "OpenClaw::CpolarWakeLock"
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
                "OpenClaw cpolar",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps cpolar running in the background"
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

        builder.setContentTitle("cpolar")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_upload)
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
        return value.replace("'", "'\\''")
    }
}
