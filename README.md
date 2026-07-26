# Agent AI Usage

English | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md)

A native macOS desktop widget for monitoring GPT / Codex and Claude usage without keeping a dashboard in front of your work.

![Agent AI Usage](docs/agent-ai-usage.png)

## Features

- Shows GPT / Codex and Claude usage in one compact native widget.
- Claude displays 5-hour, weekly, and Fable limits at the same time.
- Refreshes and re-detects services every 30 seconds.
- Attributes usage changes to the latest Codex or Claude task.
- Keeps up to three recent tasks per provider; Claude shows every changed usage window separately.
- Lives at the Finder desktop layer, behind normal application windows.
- Supports English, Simplified Chinese, Traditional Chinese, and Japanese.
- Uses native Liquid Glass on macOS 26 and a native visual-effect fallback on earlier systems.

## Data and privacy

GPT / Codex usage is read from the local Codex read-only app-server interface. Claude's 5-hour and weekly values are read from Claude Desktop's own local usage history. The app does not read, copy, or upload Claude Desktop session cookies.

Fable is a model-scoped limit that Claude Desktop may not write to its local history. If Fable shows `—`, open Settings and choose **Connect Fable usage** for one-time official Claude Code authorization. An Anthropic Admin API key with a custom monthly budget is also available as an optional fallback.

Credentials entered in Settings are stored in macOS Keychain. Usage history and the three most recent task records stay on the Mac.

## Requirements

- macOS 14 or later
- ChatGPT / Codex signed in locally for GPT usage
- Claude Desktop or Claude Code signed in locally for Claude usage
- Swift 6 command-line tools to build from source

## Build

```bash
./build.sh
```

The signed local build is written to `dist/Agent AI Usage.app`.

## Troubleshooting

- GPT missing: open ChatGPT or Codex, confirm you are signed in, then press Refresh.
- Claude missing: open Claude Desktop once so it updates its local usage history.
- Fable missing: use **Settings → Connect Fable usage**.
- The widget is missing: use the menu-bar item **Show widget on this display**.

## License

[PolyForm Noncommercial 1.0.0](LICENSE). Personal and other noncommercial use is allowed; commercial use is not licensed.

Why aren't there any other providers? Because I only subscribe to GPT and Claude.
