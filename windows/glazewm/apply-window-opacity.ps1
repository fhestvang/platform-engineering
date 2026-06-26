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
$lwaAlpha = 0x2
$focusedAlpha = [byte]245 # 96%
$otherAlpha = [byte]217   # 85%
$opaqueAlpha = [byte]255  # 100%
$processNameCache = @{}
# Last alpha actually applied per window, so we only call SetLayeredWindowAttributes
# when the target changes. Re-stamping every tick caused visible flicker during redraws.
$appliedAlpha = @{}
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

try {
  while ($true) {
    if ($null -eq (Get-Process -Name glazewm -ErrorAction SilentlyContinue)) {
      break
    }

    $foreground = [FhhWindowOpacity]::GetForegroundWindow()
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

        # Only touch the window when its opacity actually needs to change.
        if ($appliedAlpha[$hWnd] -ne $targetAlpha) {
          Set-Alpha $hWnd $targetAlpha
          $appliedAlpha[$hWnd] = $targetAlpha
        }
      } catch {
        continue
      }
    }

    if ($processNameCache.Count -gt 512) {
      $processNameCache.Clear()
      $appliedAlpha.Clear()
    }

    Start-Sleep -Milliseconds 100
  }
} finally {
  if ($createdNew) {
    $mutex.ReleaseMutex()
  }

  $mutex.Dispose()
}
