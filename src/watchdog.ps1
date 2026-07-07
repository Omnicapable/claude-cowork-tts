# watchdog.ps1 v3 - Monitors tts_watcher.py and the Kokoro TTS server.
# Restarts either one if they stop running. Checks every 30 seconds.
#
# v3 changes:
#   - Interpreter resolved via the Windows 'py -3' launcher (PATH-order independent),
#     falling back to python/python3 only if 'py' is absent.
#
# v2 changes:
#   - Port check uses BeginConnect with a 2-second timeout (v1 could hang
#     indefinitely on bad OS state, causing silent watchdog death).
#   - Watchdog log moved to %LOCALAPPDATA%\tts\watchdog.log to
#     avoid file-lock contention with the python watcher.
#   - Heartbeat line every 5 minutes so silent failure is detectable from
#     outside the process.
#   - Kokoro restarts redirect stdout/stderr to rotating log files so future
#     crashes leave a forensic trail.
#   - Loop body wrapped in try/catch so one bad iteration can't kill the loop.

$ScriptDir     = Split-Path -Parent $MyInvocation.MyCommand.Path
$WatcherScript = Join-Path $ScriptDir "tts_watcher.py"
$KokoroScript  = "$env:USERPROFILE\.claude\kokoro\tts_server.py"
# v3: resolve a concrete interpreter once via the Windows 'py -3' launcher (PATH-order
# independent, version-aware); fall back to python/python3 only if 'py' is absent.
$PythonExe     = & py -3 -c "import sys; print(sys.executable)" 2>$null
if (-not $PythonExe) {
    $PythonExe = if (Get-Command python -ErrorAction SilentlyContinue) { "python" } else { "python3" }
}
$LogDir        = Join-Path $env:LOCALAPPDATA "tts"
$LogFile       = Join-Path $LogDir "watchdog.log"
$KokoroLogDir  = Join-Path $env:LOCALAPPDATA "tts\kokoro-logs"
$Port          = 59001
$CheckInterval = 30        # seconds between checks
$ConnectTimeoutMs = 2000   # port-check timeout
$HeartbeatMins = 5         # log a heartbeat at least this often

# Ensure log dirs exist
foreach ($d in @($LogDir, $KokoroLogDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

function Write-Log($msg) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [watchdog] $msg"
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch {}
}

function Is-ProcessRunning($scriptName) {
    $procs = Get-Process python, pythonw -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        try {
            $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $($p.Id)" -ErrorAction Stop).CommandLine
            if ($cmd -like "*$scriptName*") { return $true }
        } catch {}
    }
    return $false
}

function Is-PortOpen($port, $timeoutMs) {
    $tcp = $null
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $async = $tcp.BeginConnect("127.0.0.1", $port, $null, $null)
        $waited = $async.AsyncWaitHandle.WaitOne($timeoutMs, $false)
        if (-not $waited) { return $false }
        try { $tcp.EndConnect($async); return $true } catch { return $false }
    } catch {
        return $false
    } finally {
        if ($tcp) { try { $tcp.Close() } catch {} }
    }
}

function Start-Kokoro {
    # Rotate previous logs so each restart's output is preserved
    $outLog  = Join-Path $KokoroLogDir "kokoro_server.out.log"
    $errLog  = Join-Path $KokoroLogDir "kokoro_server.err.log"
    $outPrev = Join-Path $KokoroLogDir "kokoro_server.out.prev.log"
    $errPrev = Join-Path $KokoroLogDir "kokoro_server.err.prev.log"
    if (Test-Path $outLog) { Move-Item -LiteralPath $outLog -Destination $outPrev -Force -ErrorAction SilentlyContinue }
    if (Test-Path $errLog) { Move-Item -LiteralPath $errLog -Destination $errPrev -Force -ErrorAction SilentlyContinue }
    Start-Process $PythonExe `
        -ArgumentList @('-u', "`"$KokoroScript`"") `
        -WindowStyle Hidden `
        -RedirectStandardOutput $outLog `
        -RedirectStandardError $errLog
}

function Start-Watcher {
    Start-Process $PythonExe -ArgumentList "`"$WatcherScript`"" -WindowStyle Hidden
}

Write-Log "Watchdog v2 started. Interval=${CheckInterval}s, connect timeout=${ConnectTimeoutMs}ms, heartbeat every ${HeartbeatMins}m."

$lastHeartbeat = Get-Date
$iter = 0

while ($true) {
    $iter++
    try {
        # --- Watcher check ---
        # Match the full script path so we don't false-positive on sibling
        # watchers like Codex's codex_tts_watcher.py (substring "tts_watcher").
        if (-not (Is-ProcessRunning $WatcherScript)) {
            Write-Log "tts_watcher.py not running - restarting."
            Start-Watcher
            Start-Sleep 2
            if (Is-ProcessRunning $WatcherScript) {
                Write-Log "tts_watcher.py restarted OK."
            } else {
                Write-Log "WARNING: tts_watcher.py did not start."
            }
        }

        # --- Kokoro server check ---
        $kokoroAlive = Is-PortOpen $Port $ConnectTimeoutMs
        if (-not $kokoroAlive) {
            $procAlive = Is-ProcessRunning "tts_server"
            Write-Log "Kokoro server not responding on port $Port (process alive=$procAlive) - restarting."
            # If a stale process is hanging on the socket, kill it first
            if ($procAlive) {
                Get-Process python -ErrorAction SilentlyContinue | Where-Object {
                    try { (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction Stop).CommandLine -like '*tts_server*' }
                    catch { $false }
                } | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep 1
            }
            Start-Kokoro
            Start-Sleep 6
            if (Is-PortOpen $Port $ConnectTimeoutMs) {
                Write-Log "Kokoro server restarted successfully."
            } else {
                Write-Log "WARNING: Kokoro server still not responding after restart. Check kokoro_server.err.log."
            }
        }

        # --- Heartbeat ---
        if (((Get-Date) - $lastHeartbeat).TotalMinutes -ge $HeartbeatMins) {
            Write-Log "Heartbeat: iter=$iter watcher=$(Is-ProcessRunning $WatcherScript) kokoro=$(Is-PortOpen $Port $ConnectTimeoutMs)"
            $lastHeartbeat = Get-Date
        }
    } catch {
        Write-Log "Loop iteration error: $($_.Exception.Message)"
    }

    Start-Sleep $CheckInterval
}
