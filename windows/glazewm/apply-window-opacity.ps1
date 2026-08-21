# Own per-window opacity outside GlazeWM so Chrome can be exempted reliably.
# GlazeWM's global window_effects transparency resets manual overrides on focus.
$createdNew = $false
$mutex = [System.Threading.Mutex]::new($true, 'Local\FhhApplyWindowOpacity', [ref]$createdNew)

if (-not $createdNew) {
  exit 0
}

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class FhhWindowOpacity {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern bool IsWindowVisible(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();

  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

  [DllImport("user32.dll", EntryPoint = "GetWindowLong", SetLastError = true)]
  public static extern IntPtr GetWindowLong32(IntPtr hWnd, int nIndex);

  [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr", SetLastError = true)]
  public static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);

  [DllImport("user32.dll", EntryPoint = "SetWindowLong", SetLastError = true)]
  public static extern IntPtr SetWindowLong32(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

  [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr", SetLastError = true)]
  public static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool SetLayeredWindowAttributes(
    IntPtr hwnd,
    uint crKey,
    byte bAlpha,
    uint dwFlags
  );

  [DllImport("user32.dll", SetLastError = true)]
  public static extern bool GetLayeredWindowAttributes(
    IntPtr hwnd,
    out uint crKey,
    out byte bAlpha,
    out uint dwFlags
  );

  public static IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex) {
    return IntPtr.Size == 8
      ? GetWindowLongPtr64(hWnd, nIndex)
      : GetWindowLong32(hWnd, nIndex);
  }

  public static IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong) {
    return IntPtr.Size == 8
      ? SetWindowLongPtr64(hWnd, nIndex, dwNewLong)
      : SetWindowLong32(hWnd, nIndex, dwNewLong);
  }
}
'@

$gwlExStyle = -20
$wsExLayered = 0x00080000
$lwaColorKey = 0x1
$lwaAlpha = 0x2
$focusedAlpha = [byte]245 # 96%
$otherAlpha = [byte]217   # 85%
$opaqueAlpha = [byte]255  # 100%
$processNameCache = @{}
$excludedProcesses = @(
  'ApplicationFrameHost',
  'explorer',
  'glazewm',
  'ShellExperienceHost',
  'StartMenuExperienceHost',
  'SearchHost',
  'TextInputHost',
  'yasb',
  'zebar'
)

function Set-Alpha($hWnd, [byte]$alpha) {
  $style = [FhhWindowOpacity]::GetWindowLongPtr($hWnd, $gwlExStyle).ToInt64()

  if (($style -band $wsExLayered) -eq 0) {
    [void][FhhWindowOpacity]::SetWindowLongPtr(
      $hWnd,
      $gwlExStyle,
      [System.IntPtr]($style -bor $wsExLayered)
    )
  }

  [void][FhhWindowOpacity]::SetLayeredWindowAttributes($hWnd, 0, $alpha, $lwaAlpha)
}

$lastForeground = [System.IntPtr]::Zero
$ticksSinceSweep = 10

try {
  while ($true) {
    # The full EnumWindows sweep through PowerShell callbacks costs ~9% of a core
    # at 10Hz, so each 100ms tick only makes one native call. Sweep on focus
    # change (the visible transition must stay instant) or every 10th tick — the
    # 1s fallback still catches new unfocused windows and DWM resetting layered
    # attributes on display changes/resume.
    $foreground = [FhhWindowOpacity]::GetForegroundWindow()
    $ticksSinceSweep++
    if ($foreground -eq $lastForeground -and $ticksSinceSweep -lt 10) {
      Start-Sleep -Milliseconds 100
      continue
    }
    $lastForeground = $foreground
    $ticksSinceSweep = 0

    if ($null -eq (Get-Process -Name glazewm -ErrorAction SilentlyContinue)) {
      break
    }

    $windows = [System.Collections.Generic.List[System.IntPtr]]::new()
    $callback = [FhhWindowOpacity+EnumWindowsProc]{
      param([System.IntPtr]$hWnd, [System.IntPtr]$lParam)

      if ([FhhWindowOpacity]::IsWindowVisible($hWnd)) {
        [void]$windows.Add($hWnd)
      }

      return $true
    }

    [void][FhhWindowOpacity]::EnumWindows($callback, [System.IntPtr]::Zero)

    foreach ($hWnd in $windows) {
      try {
        [uint32]$procId = 0
        [void][FhhWindowOpacity]::GetWindowThreadProcessId($hWnd, [ref]$procId)

        if ($procId -eq 0) {
          continue
        }

        $processName = $processNameCache[$procId]
        if ($null -eq $processName) {
          $process = Get-Process -Id $procId -ErrorAction SilentlyContinue
          if ($null -eq $process) {
            continue
          }

          $processName = $process.ProcessName
          $processNameCache[$procId] = $processName
        }

        if ($processName -in $excludedProcesses) {
          continue
        }

        if ($processName -in @('chrome', 'chrome_proxy')) {
          $targetAlpha = $opaqueAlpha
        } elseif ($hWnd -eq $foreground) {
          $targetAlpha = $focusedAlpha
        } else {
          $targetAlpha = $otherAlpha
        }

        # Read the actual alpha back from the window instead of caching it: hWnd
        # values are reused for new windows, and DWM resets layered attributes on
        # display changes/resume — a cache goes stale on both and windows end up
        # stuck at the wrong opacity. Only touch the window when it differs.
        $style = [FhhWindowOpacity]::GetWindowLongPtr($hWnd, $gwlExStyle).ToInt64()
        if (($style -band $wsExLayered) -ne 0) {
          [uint32]$curKey = 0; [byte]$curAlpha = 0; [uint32]$curFlags = 0
          $readable = [FhhWindowOpacity]::GetLayeredWindowAttributes(
            $hWnd, [ref]$curKey, [ref]$curAlpha, [ref]$curFlags)

          # Unreadable = per-pixel alpha (UpdateLayeredWindow); color-keyed windows
          # would lose their key if we stamped LWA_ALPHA over it. Leave both alone.
          if (-not $readable -or ($curFlags -band $lwaColorKey) -ne 0) {
            continue
          }

          if (($curFlags -band $lwaAlpha) -ne 0 -and $curAlpha -eq $targetAlpha) {
            continue
          }
        }

        Set-Alpha $hWnd $targetAlpha
      } catch {
        continue
      }
    }

    if ($processNameCache.Count -gt 512) {
      $processNameCache.Clear()
    }

    Start-Sleep -Milliseconds 100
  }
} finally {
  if ($createdNew) {
    $mutex.ReleaseMutex()
  }

  $mutex.Dispose()
}
