#Requires AutoHotkey v2.0
#SingleInstance Force

; Tap the Windows key on its own  ->  open PowerToys Run (Ctrl+Alt+Space).
; Win + any other key (Win+L, Win+E, Win+Shift+S, Win+V, ...) keeps working normally.
;
; How it works: on Win-down we inject a harmless no-op key (vkE8). That "spoils"
; the lone-Win press Windows uses to open the Start menu, but the '~' prefix keeps
; the real Win key held, so combinations still register. On Win-up, if the only
; thing that happened was our no-op, it was a solo tap -> fire the launcher.

~LWin::Send("{Blind}{vkE8}")
~LWin Up:: {
    ; Solo tap = the last real key before this release was Win itself (or only our
    ; injected no-op). A combo leaves some other key (e, l, ...) as the prior key.
    if (A_PriorKey = "LWin" || A_PriorKey = "vkE8")
        SendEvent("^!{Space}")   ; Ctrl+Alt+Space = PowerToys Run
}
