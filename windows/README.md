# Windows window-manager configs

Tracked copies of the laptop's Windows-side WM configs:

| repo file                   | Windows target                                              |
| --------------------------- | ---------------------------------------------------------- |
| `glazewm/config.yaml`       | `%USERPROFILE%\.glzr\glazewm\config.yaml`                  |
| `glazewm/apply-window-opacity.ps1` | `%USERPROFILE%\.glzr\glazewm\apply-window-opacity.ps1` |
| `glazewm/fhh-shell-watchdog.ps1` | `%USERPROFILE%\.glzr\glazewm\fhh-shell-watchdog.ps1`  |
| `yasb/config.yaml`          | `%USERPROFILE%\.config\yasb\config.yaml`                   |
| `yasb/styles.css`           | `%USERPROFILE%\.config\yasb\styles.css`                    |
| `ahk/win-launcher.ahk`      | `%USERPROFILE%\.config\ahk\win-launcher.ahk`               |
| `youtube-music/fhh-mono.css`| `%APPDATA%\YouTube Music\themes\fhh-mono.css`              |

Only the portable theme file is tracked for th-ch/youtube-music; its `config.json`
is left out — it holds machine-specific, volatile state (window positions, exe
paths, the current track URL).

`ahk/win-launcher.ahk` makes a **solo tap of the Windows key open PowerToys Run**
(while Win+key combos still work). Setup is not just this file — see
"App launcher" below.

These live **outside** the chezmoi root (`home/`), so `chezmoi apply` ignores
them. They can't be symlinked across the WSL/Windows boundary (Developer Mode is
off), so they're synced as copies with `sync-to-windows.sh`.

## Usage (run in WSL on the laptop)

```sh
./sync-to-windows.sh          # push repo -> Windows, reload YASB
./sync-to-windows.sh --pull   # capture live edits Windows -> repo, then commit
```

After a push, both YASB and GlazeWM are reloaded automatically. GlazeWM is
uiAccess (not admin-elevated): process control from WSL fails with
ERROR_ELEVATION_REQUIRED, but its websocket IPC on `ws://localhost:6123` accepts
`command wm-reload-config` / `command wm-redraw` / `query ...` from any process,
which is what the script uses. Alt+Shift+R remains as the manual fallback.

## Shell watchdog

`glazewm/fhh-shell-watchdog.ps1` runs permanently (started by GlazeWM's
startup/reload commands and a Startup-folder shortcut; a mutex dedups). Every
20s it:

- issues `wm-redraw` when GlazeWM's PID changes — GlazeWM 3.10.1 crashes
  (access violation, fixed offset) and WER auto-restarts it, but on mixed-DPI
  monitors (125% laptop / 100% external) the re-tiled windows land at ~1/1.25
  of their intended size until a redraw;
- restarts GlazeWM after a crash *without* auto-restart (Event 1000 within 3
  min; deliberate `wm-exit` is left alone; max 3 restarts per 30 min);
- starts YASB when it's dead, and force-restarts it when hung (process alive
  but zero visible windows for 60s — the "Timeout waiting for previous
  instance" failure after screen changes);
- restarts the opacity script if it exited.

Actions are logged to `%USERPROFILE%\.glzr\glazewm\watchdog.log`.

## App launcher (PowerToys Run, opened by the Windows key)

The launcher is **PowerToys Run**, triggered by tapping the **Windows key**.
Flow Launcher was removed (2026-06-26) after days of it not taking keyboard focus
under GlazeWM. PowerToys Run is enabled in PowerToys settings with its activation
shortcut left at **Ctrl+Alt+Space** (deliberately *not* bare Alt+Space, which
collides with GlazeWM's Alt modifier). `win-launcher.ahk` then maps a solo Win tap
to that shortcut.

On a fresh machine, three steps beyond the file sync:

1. `winget install AutoHotkey.AutoHotkey --scope user`
2. PowerToys → enable **PowerToys Run** (or set `"PowerToys Run": true` in
   `%LOCALAPPDATA%\Microsoft\PowerToys\settings.json` while PowerToys is stopped).
3. Autostart the script — create a Startup shortcut (run in WSL):
   ```sh
   powershell.exe -NoProfile -Command "
   \$ws=New-Object -ComObject WScript.Shell
   \$l=\$ws.CreateShortcut(\"\$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\WinKey-Launcher.lnk\")
   \$l.TargetPath=\"\$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe\"
   \$l.Arguments='\"'+\$env:USERPROFILE+'\.config\ahk\win-launcher.ahk\"'
   \$l.Save()"
   ```

GlazeWM ignores the PowerToys Run window (`PowerToys.PowerLauncher` in the ignore
rules) so it isn't tiled and keeps keyboard focus.
