<img width="250" height="292" alt="tokenbar" src="https://github.com/user-attachments/assets/ddd8a462-c6ed-4e2f-98cf-0610aa53bf95" />


# TokenBar

A lightweight macOS menu bar app that shows your **Claude.ai** and **Codex (ChatGPT)** usage limits at a glance — so you always know how much of your plan you've used.

![macOS](https://img.shields.io/badge/macOS-13.0+-black)
![License](https://img.shields.io/badge/license-MIT%20%2B%20Commons%20Clause-blue)
![Version](https://img.shields.io/badge/version-1.07-green)

## Features

- **Claude.ai usage** — current session and weekly token usage with a visual progress bar
- **Session reset timer** — countdown to your next session reset
- **Codex usage** — current ChatGPT/Codex session usage
- **Task tracking** — track active Claude Code tasks with a live timer
- **Auto-update** — built-in updater, installs new versions without opening a browser
- **URL scheme** — start and complete tasks via `tokenbar://start` and `tokenbar://done`
- Supports **English, Polish, German, French, Spanish**

## Installation

1. Download the latest `TokenBar.dmg` from [Releases](https://github.com/buzzyrobot/tokenbar/releases)
2. Open the DMG and drag **TokenBar.app** to `/Applications`
3. Launch TokenBar — it will appear in your menu bar
4. Click the icon and sign in to Claude.ai when prompted

## Requirements

- macOS 13.0 or later
- A [Claude.ai](https://claude.ai) account (Pro or higher for usage limits)

## URL Scheme

Integrate TokenBar with Claude Code or other tools:

```bash
# Start a task
open "tokenbar://start?name=My+Task"

# Complete a task
open "tokenbar://done?name=My+Task"
```

## Auto-update

TokenBar checks for updates automatically. You can also check manually via the gear icon → **Check for Updates**. Updates are downloaded and installed in-app — no browser required.

## Building from Source

```bash
git clone https://github.com/buzzyrobot/tokenbar.git
cd tokenbar
open ClaudeTrack.xcodeproj
```

Requires Xcode 15+ and macOS 13 SDK.

## License

[MIT + Commons Clause](LICENSE) — free to use and modify, but not for commercial purposes.

---

Made by [buzzyrobot](https://github.com/buzzyrobot)
