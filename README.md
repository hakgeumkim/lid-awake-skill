# lid-awake-skill

An agent skill that builds LidAwake, a tiny macOS menu bar app: **keep a MacBook awake with the lid closed while it is on the charger, and let it sleep normally on battery.**

Useful when a MacBook doubles as a home server: a Claude Code Remote Control host, tmux sessions, a dev server, a download.

- **On the charger:** close the lid and the Mac keeps running. The screen turns off right away, and opening the lid shows the lock screen.
- **On battery:** the Mac sleeps as usual, so it is safe in a bag. Unplug with the lid closed and it goes to sleep immediately.
- **Idle:** normal display sleep and video wake locks are untouched. Full-screen video does not lock the screen.

## Why not `pmset -c disablesleep 1`?

`disablesleep` is the only switch that stops lid-close sleep without an external display, but it is **one system-wide value**. `-a`, `-b` and `-c` all set the same flag ([Apple's PowerManagement source](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m): "system-wide settings, not tied to power source"). So `sudo pmset -c disablesleep 1` also keeps the Mac awake on battery. `caffeinate` cannot stop lid-close sleep at all.

LidAwake listens for power-source changes (IOKit notification, no polling) and flips the flag: `1` on AC, `0` on battery. Amphetamine's closed-display mode uses the same flag, but its sessions also hold a display-sleep assertion, which can lock the screen during video. LidAwake never touches display sleep.

## Install the skill

Claude Code:

```bash
git clone https://github.com/hakgeumkim/lid-awake-skill ~/.claude/skills/lid-awake
```

Codex and other agents that read `~/.agents/skills`:

```bash
git clone https://github.com/hakgeumkim/lid-awake-skill ~/.agents/skills/lid-awake
```

Then ask your agent: "Keep my MacBook awake with the lid closed when it's on the charger."

## Build without an agent

```bash
./build.sh                    # compiles and installs ~/Applications/LidAwake.app, then starts it
sudo ./install-sudoers.sh     # once: lets the app run pmset without a password
```

`install-sudoers.sh` adds `/etc/sudoers.d/lid-awake`, which allows your user exactly three commands and nothing else:

```
/usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset sleepnow
```

The file is checked with `visudo -cf` before it is installed. Turn on **로그인 시 실행** (Launch at Login) in the menu bar menu. See [SKILL.md](SKILL.md) for testing and uninstall steps.

## Requirements

- macOS 13 or later, a MacBook
- Xcode Command Line Tools (`xcode-select --install`)
- For lock-on-lid-close: System Settings → Lock Screen → require password **immediately** after the display turns off

## Known limits

- If the app crashes while on the charger, the flag stays on until the app starts again. Check with `pmset -g | grep SleepDisabled`.
- Menu labels are in Korean. Change them in `main.swift`.

## License

MIT
