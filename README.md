# whispr-gateway

A tiny macOS menu bar app that lets you speak text into any app on your Mac — using Telegram as the bridge.

## The idea

[Wispr Flow](https://wisprflow.ai) is a great speech-to-text tool, but the free quota runs out fast. Telegram on Android, on the other hand, has built-in voice-to-text that's basically unlimited (for now). So why not use that?

whispr-gateway sits in your menu bar and watches your Telegram bot. When you dictate a message on your phone, it shows up on your Mac — pasted wherever your cursor is. VS Code, Terminal, browser, Claude Code, doesn't matter.

## How it works

```
You speak → Telegram (Android) → Telegram Bot → Mac app → pastes text
```

That's it.

## Install

**1. Get your Telegram credentials**

- Create a bot via [@BotFather](https://t.me/botfather) → copy the `BOT_TOKEN`
- Send any message to your new bot, then open this URL in a browser:
  ```
  https://api.telegram.org/bot<BOT_TOKEN>/getUpdates
  ```
  Find `"chat": { "id": 123456 }` — that number is your `CHAT_ID`

**2. Set up config**

```bash
cp config.env.example config.env
```

Open `config.env` and fill in your `BOT_TOKEN` and `CHAT_ID`.

**3. Build the app**

```bash
bash make-app.sh
```

This creates `WhisprGateway.app` in the project folder.

**4. Install**

Drag `WhisprGateway.app` to your `/Applications` folder.

**5. First launch**

Right-click → Open (macOS will ask you to confirm since it's not from the App Store).

Grant **Accessibility permission** when prompted — this is required for the auto-paste to work.
> System Settings → Privacy & Security → Accessibility → enable WhisprGateway

**6. Use it**

Click the mic icon in the menu bar → flip the toggle to activate → speak on Telegram → text appears on your Mac.

## Requirements

- macOS 13+
- Swift (comes with Xcode Command Line Tools — run `xcode-select --install` if missing)

## Dev

```bash
swift run   # run without building a .app
```
