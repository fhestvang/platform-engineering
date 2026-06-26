# Windows window-manager configs

Tracked copies of the laptop's Windows-side WM configs:

| repo file                   | Windows target                                              |
| --------------------------- | ---------------------------------------------------------- |
| `glazewm/config.yaml`       | `%USERPROFILE%\.glzr\glazewm\config.yaml`                  |
| `glazewm/apply-window-opacity.ps1` | `%USERPROFILE%\.glzr\glazewm\apply-window-opacity.ps1` |
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

After a push, press **Alt+Shift+R** to reload GlazeWM (it runs elevated, so the
script can't reload it for you). YASB is reloaded automatically.

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
