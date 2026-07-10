# Keep the desktop shell (GlazeWM + YASB + opacity script) alive without manual
# restarts. Observed failure modes this covers:
#   - GlazeWM 3.10.1 crashes (AV at fixed offset). WER usually restarts it, but the
#     re-tiled windows land at wrong physical positions on mixed-DPI monitors
#     (125% laptop / 100% external) until a wm-redraw — so redraw after every
#     restart we detect.
#   - YASB's self-reload on "Screens updated" (dock/undock, resume) can hit
#     "Timeout waiting for previous instance" and abort, leaving a dead or hung
#     bar process with no visible windows.
#   - The opacity script exits when GlazeWM dies and nothing restarts it if
#     GlazeWM never re-runs its startup_commands.
#
# GlazeWM has uiAccess=true, so it cannot be launched via bare CreateProcess
# (ERROR_ELEVATION_REQUIRED) — Start-Process (ShellExecute) is required. Control
# goes through its websocket IPC on ws://localhost:6123.

$createdNew = $false
$mutex = [System.Threading.Mutex]::new($true, 'Local\FhhShellWatchdog', [ref]$createdNew)
if (-not $createdNew) {
  exit 0
}

$glazeExe = 'C:\Program Files\glzr.io\GlazeWM\glazewm.exe'
$yasbDir = 'C:\Program Files\YASB'
$opacityScript = Join-Path $env:USERPROFILE '.glzr\glazewm\apply-window-opacity.ps1'
$logFile = Join-Path $env:USERPROFILE '.glzr\glazewm\watchdog.log'

function Write-Log([string]$msg) {
  if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 256KB) {
    Clear-Content $logFile
  }
  "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg" | Add-Content $logFile
}

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class FhhWatchdogWin32 {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern bool IsWindowVisible(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
}
'@

function Invoke-GlazeCommand([string]$message) {
  # Talk to GlazeWM's IPC directly; works from any integrity level.
  try {
    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    $ct = [System.Threading.CancellationToken]::None
    $ws.ConnectAsync([Uri]'ws://localhost:6123', $ct).Wait(3000) | Out-Null
    $bytes = [Text.Encoding]::UTF8.GetBytes($message)
    $seg = [ArraySegment[byte]]::new($bytes)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait(3000) | Out-Null
    $buf = [ArraySegment[byte]]::new([byte[]]::new(65536))
    $ws.ReceiveAsync($buf, $ct).Wait(3000) | Out-Null
    $ws.Dispose()
    return $true
  } catch {
    return $false
  }
}

function Get-VisibleWindowCount([int[]]$processIds) {
  # Collected via .Add on a captured list — a plain counter assignment inside the
  # callback would write to a scriptblock-local copy and never reach this scope.
  $hits = [System.Collections.Generic.List[int]]::new()
  $callback = [FhhWatchdogWin32+EnumWindowsProc]{
    param([IntPtr]$hWnd, [IntPtr]$lParam)

    [uint32]$procId = 0
    [void][FhhWatchdogWin32]::GetWindowThreadProcessId($hWnd, [ref]$procId)
    if ($procId -in $processIds -and [FhhWatchdogWin32]::IsWindowVisible($hWnd)) {
      [void]$hits.Add(1)
    }

    return $true
  }
  [void][FhhWatchdogWin32]::EnumWindows($callback, [IntPtr]::Zero)
  return $hits.Count
}

function Test-RecentGlazeCrash {
  # Deliberate wm-exit leaves no Application Error event; a crash does. Only
  # resurrect GlazeWM after a crash, never override an intentional exit.
  $events = Get-WinEvent -FilterHashtable @{
    LogName = 'Application'; Id = 1000; StartTime = (Get-Date).AddMinutes(-3)
  } -ErrorAction SilentlyContinue
  return [bool]($events | Where-Object { $_.Message -match 'glazewm' })
}

Write-Log 'watchdog started'

$lastGlazePid = $null
$glazeRestartTimes = [System.Collections.Generic.List[datetime]]::new()
$yasbMissingTicks = 0
$yasbHungTicks = 0
$loggedDeliberateExit = $false

try {
  while ($true) {
    $glaze = Get-Process -Name glazewm -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($null -ne $glaze) {
      $loggedDeliberateExit = $false

      if ($null -ne $lastGlazePid -and $glaze.Id -ne $lastGlazePid) {
        # GlazeWM came back with a new PID (WER auto-restart after a crash).
        # Physical window positions are unreliable on mixed-DPI setups until a
        # redraw, so force one once the IPC server is up.
        Write-Log "glazewm restarted (pid $lastGlazePid -> $($glaze.Id)); issuing wm-redraw"
        Start-Sleep -Seconds 5
        if (-not (Invoke-GlazeCommand 'command wm-redraw')) {
          Start-Sleep -Seconds 5
          [void](Invoke-GlazeCommand 'command wm-redraw')
        }
      }
      $lastGlazePid = $glaze.Id

      # --- YASB: dead bar ---
      $yasb = @(Get-Process -Name yasb -ErrorAction SilentlyContinue)
      if ($yasb.Count -eq 0) {
        $yasbMissingTicks++
        $yasbHungTicks = 0
        # Two-tick grace: right after a GlazeWM start its startup_commands are
        # already starting YASB; racing a second start can itself trigger the
        # "waiting for previous instance" timeout.
        if ($yasbMissingTicks -ge 2) {
          Write-Log 'yasb not running; starting'
          Start-Process -FilePath (Join-Path $yasbDir 'yasbc.exe') -ArgumentList 'start' `
            -WorkingDirectory $yasbDir -WindowStyle Hidden
          $yasbMissingTicks = 0
        }
      } else {
        $yasbMissingTicks = 0

        # --- YASB: hung bar (process alive, no visible windows) ---
        $windowCount = Get-VisibleWindowCount ($yasb | ForEach-Object { $_.Id })
        if ($windowCount -eq 0) {
          $yasbHungTicks++
          if ($yasbHungTicks -ge 3) {
            Write-Log "yasb hung (no visible windows for $yasbHungTicks ticks); force-restarting"
            $yasb | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Start-Process -FilePath (Join-Path $yasbDir 'yasbc.exe') -ArgumentList 'start' `
              -WorkingDirectory $yasbDir -WindowStyle Hidden
            $yasbHungTicks = 0
          }
        } else {
          $yasbHungTicks = 0
        }
      }

      # --- Opacity script ---
      try {
        $opacityMutex = [System.Threading.Mutex]::OpenExisting('Local\FhhApplyWindowOpacity')
        $opacityMutex.Dispose()
      } catch {
        Write-Log 'opacity script not running; starting'
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
          '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
          '-File', $opacityScript
        )
      }
    } else {
      $lastGlazePid = $null
      $yasbMissingTicks = 0
      $yasbHungTicks = 0

      if (Test-RecentGlazeCrash) {
        # Crash-loop guard: at most 3 resurrections per 30 minutes.
        $cutoff = (Get-Date).AddMinutes(-30)
        while ($glazeRestartTimes.Count -gt 0 -and $glazeRestartTimes[0] -lt $cutoff) {
          $glazeRestartTimes.RemoveAt(0)
        }

        if ($glazeRestartTimes.Count -lt 3) {
          Write-Log 'glazewm crashed without auto-restart; starting'
          $glazeRestartTimes.Add((Get-Date))
          Start-Process -FilePath $glazeExe
          Start-Sleep -Seconds 8
          [void](Invoke-GlazeCommand 'command wm-redraw')
        }
      } elseif (-not $loggedDeliberateExit) {
        Write-Log 'glazewm not running, no recent crash event; assuming deliberate exit'
        $loggedDeliberateExit = $true
      }
    }

    Start-Sleep -Seconds 20
  }
} finally {
  if ($createdNew) {
    $mutex.ReleaseMutex()
  }

  $mutex.Dispose()
}
