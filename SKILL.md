---
name: lid-awake
description: Build and install LidAwake, a small macOS menu bar app that keeps a MacBook awake with the lid closed while it is on AC power, and lets it sleep normally on battery. Use it when the user wants the Mac to keep running a server, a Remote Control host, or tmux sessions with the lid closed on the charger, or asks about clamshell sleep, `pmset disablesleep`, or replacing Amphetamine.
---

# LidAwake

A native menu bar app built from source on the user's Mac (same pattern as text-reminder). No Apple Developer account and no Gatekeeper warning.

## Why it exists

- `pmset disablesleep` is the only switch that stops lid-close sleep without an external display. It is one system-wide value: `-a`, `-b` and `-c` all set the same flag (Apple PowerManagement source: "system-wide settings, not tied to power source"). So `sudo pmset -c disablesleep 1` also blocks sleep on battery.
- `caffeinate` and IOKit sleep assertions do not stop lid-close sleep.
- Amphetamine uses the same flag (it installs `/etc/sudoers.d/amphetamine_PowerProtect` and reads `AppleClamshellState`), but its sessions also hold a display-sleep assertion. With it running, the screen locked during full-screen video (turg 2026-10-21). LidAwake never touches display sleep.

## What the app does

- On every plug or unplug (IOKit power-source notification, no polling) it sets `disablesleep 1` on AC and `0` on battery.
- If the Mac is unplugged with the lid already closed, it also runs `pmset sleepnow`.
- When the lid closes while it stays awake, it runs `pmset displaysleepnow`: the screen goes black, and with "require password immediately" (`sysadminctl -screenLock status` → immediate) opening the lid shows the lock screen. Lid events come from the IOPMrootDomain clamshell interest notification (`0xe0034100`).
- On quit (and logout or shutdown) it sets `disablesleep 0`.
- Menu: status line, 켜기/끄기, 로그인 시 실행, 종료. Icon: `laptopcomputer` = stays awake with the lid closed, `moon.zzz` = sleeps normally.
- Setting: `defaults read com.hakgeumkim.LidAwake enabled` (default true).

## Files

| File | Purpose |
|---|---|
| `main.swift` | The whole app (AppKit + IOKit, one file) |
| `Info.plist` | Bundle settings. `LSUIElement` hides the Dock icon. |
| `build.sh` | Compiles, installs to `~/Applications/LidAwake.app`, starts it |
| `install-sudoers.sh` | Installs `/etc/sudoers.d/lid-awake`: the user may run only `pmset -a disablesleep 0`, `pmset -a disablesleep 1` and `pmset sleepnow` without a password. Checked with `visudo -cf`. |

## Procedure

1. `xcode-select -p` must succeed (else `xcode-select --install`).
2. Run `./build.sh` in this folder.
3. The user runs `sudo ./install-sudoers.sh` once (needs their password; the agent cannot do it). Until then the menu shows "권한 없음".
4. Turn on 로그인 시 실행 in the menu.
5. Test, then check with `pmset -g log | grep -i 'clamshell'` and `pmset -g | grep SleepDisabled`:
   - On AC, close the lid for 1 minute: no new "Clamshell Sleep" entry, `SleepDisabled 1`.
   - On battery, close the lid for 1 minute: a "Clamshell Sleep ... Using Batt" entry.

## Uninstall

1. Quit from the menu (this resets `disablesleep 0`). Turn off 로그인 시 실행 first.
2. Delete `~/Applications/LidAwake.app`.
3. `sudo rm /etc/sudoers.d/lid-awake`
4. `defaults delete com.hakgeumkim.LidAwake`

## Known limits

- If the app crashes on AC, `SleepDisabled` stays 1 until it starts again. Check `pmset -g | grep SleepDisabled`; fix with `sudo pmset -a disablesleep 0`.
- A closed MacBook in a bag does not sleep while the flag is 1. The flag drops to 0 as soon as the charger is unplugged, but only while the app is running.
- `pmset sleepnow` after unplugging with the lid closed follows another project's design (awake-on-ac); it is not yet verified on this Mac.
