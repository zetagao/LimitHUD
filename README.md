<div align="center">
  <img src="docs/icon.png" width="120" alt="LimitHUD icon">
  <h1>LimitHUD</h1>
  <p>A floating macOS HUD that keeps a live eye on your <b>Claude</b> and <b>Codex (ChatGPT)</b> usage quotas — and warns you before you run out.</p>
  <p>Stays out of your menu bar · floats above everything · fully customizable reminders & looks.</p>
</div>

---

## Features

### Quota monitoring
- **Both providers, real numbers** — Claude and Codex (ChatGPT), straight from each service's own usage API (not estimates).
- **Claude**: `5-Hour` and `7-Day` windows, plus per-model weekly limits (`Opus`, `Sonnet`, hidden by default).
- **Codex**: `5-Hour` (primary) and `7-Day` (secondary/weekly) windows.
- Everything is shown as **remaining** (`% left`), not used.
- **Auto-refresh** every 30s / 1min / 5min, with a **reset countdown** per window (e.g. `2h13m`, `3d20h`).
- Graceful error rows per provider (not signed in / session expired / HTTP error) — never crashes, never blocks the other provider.

### The floating card
- Floats on screen, **always on top** across every Space and over other apps' full-screen — until you close it.
- **Draggable** anywhere.
- Quiet dark design — solid frosted surface, hairline border, monospaced uppercase system labels.
- **Semantic progress bars**: green > 50%, amber 20–50%, red < 20%.
- `SYNCED HH:mm` timestamp, refreshed each minute.
- **Follows the system light/dark appearance** automatically.
- Close via the card's ✕, the menu-bar icon, or the global hotkey.

### Menu bar
- A **single icon** (8 styles to pick from, switchable live), so it barely takes a slot.
- **Left-click** toggles the card (pops up right under the icon).
- **Right-click** menu: Settings… / Refresh / Quit.

### Reminders
- **Low-quota alert** — a system notification when any window drops below your threshold (default 20%).
- **Recovery reminder** — a notification when a window resets back above the threshold.
- Edge-detected, so it fires once per crossing (no spam).
- System notification + sound toggles.

### Settings (⚙ / right-click → Settings… / ⌘,)
- **Reminders** — alert on/off, threshold %, recovery reminder, notifications, sound.
- **Sources** — Claude / Codex toggles.
- **Card content** — per-window toggles to choose exactly what shows.
- **Refresh** — 30s / 1min / 5min.
- **Card** — **custom global hotkey** (record any combo), launch at login, opacity.

---

## Privacy & Security

LimitHUD reads your **Chrome session cookies locally** to call each service's own usage endpoint:

- Cookies are decrypted **on-device** (Chrome's SQLite store + the encryption key from your login Keychain) and used **only** as the `Cookie` header to `claude.ai` / `chatgpt.com`.
- **Nothing is sent anywhere else.** No servers, no analytics, no telemetry.
- The whole thing is open source — audit it.
- On first run macOS asks once for **Keychain access** (to read Chrome's key) and once for **notifications**. Click Allow.

---

## Requirements

- macOS 13+
- Signed into `claude.ai` and/or `chatgpt.com` in **Google Chrome**
- A Swift toolchain to build (Xcode **or** Command Line Tools — full Xcode not required)

## Build & Install

```bash
./setup-signing.sh    # once: create a stable self-signed code-signing cert
./build.sh            # compile + sign  →  LimitHUD.app
./build.sh run        # build and launch
./build.sh install    # build, install to /Applications, launch
```

The self-signed cert keeps the app's code identity stable across rebuilds, so the Keychain "Always Allow" sticks.

To regenerate the app icon:

```bash
swift tools/icongen.swift AppIcon.iconset && iconutil -c icns AppIcon.iconset -o AppIcon.icns
```

## How it works

- **Swift + SwiftUI + AppKit**, built with Swift Package Manager — **no Xcode project needed** (`build.sh` assembles the `.app` by hand).
- The card is a borderless, non-activating `NSPanel` at `.statusBar` level hosting a SwiftUI view.
- Chrome cookie decryption: read the Cookies SQLite DB → fetch the `Chrome Safe Storage` key from the Keychain → PBKDF2-SHA1 (salt `saltysalt`, 1003 rounds) → AES-128-CBC (handling the 32-byte domain-hash prefix on Chrome ≥ v24). A small system module (`CBridge`) bridges `sqlite3` + `CommonCrypto`.

## License

MIT — see [LICENSE](LICENSE).

---

<details>
<summary><b>中文说明</b></summary>

## 简介

一个 macOS 悬浮小工具，实时盯着 **Claude** 与 **Codex (ChatGPT)** 的额度，快用完前提醒你。不占菜单栏、悬浮在屏幕、可自定义提醒与外观。

## 功能

**额度监控**
- 两家**官方真实额度**（非估算）：Claude（`5-Hour`/`7-Day`，外加分模型周额度 `Opus`/`Sonnet`，默认隐藏）、Codex（`5-Hour` 主 / `7-Day` 次）。
- 统一显示**剩余**（`% left`）；自动刷新（30s/1min/5min）；每窗口**重置倒计时**。
- 按家显示错误态（未登录/失效/报错），不崩、不连累另一家。

**悬浮卡片**
- 屏幕悬浮、**始终置顶**（跨桌面、盖全屏），可拖动。
- 克制暗色设计、等宽大写标签、**三档语义色进度条**（绿/黄/红）。
- 左下角 `SYNCED HH:mm`；**跟随系统明暗自动切换**。
- 三种关闭：卡片 ✕ / 菜单栏图标 / 全局快捷键。

**菜单栏**：单图标（8 种样式可换），左键显隐（贴图标下方弹出），右键菜单 Settings… / Refresh / Quit。

**提醒**：低额阈值告警（默认 <20%）、额度恢复提醒、边沿检测不刷屏、通知+声音开关。

**设置（5 组）**：REMINDERS（告警/阈值/恢复/通知/声音）、SOURCES（Claude/Codex 开关）、CARD CONTENT（逐窗口自定义显示）、REFRESH（间隔）、CARD（**自定义快捷键**/开机自启/透明度）。

## 隐私与安全

LimitHUD 在**本地**读取 Chrome 登录 cookie，仅用于调用各服务自己的额度接口：cookie 在本机解密（SQLite + 你的登录钥匙串），**只**作为 `Cookie` 头发给 `claude.ai` / `chatgpt.com`，**不外传任何地方**，无服务器、无统计。代码开源可审计。首次运行会各弹一次钥匙串授权与通知授权，点允许即可。

## 环境要求
- macOS 13+
- 用 **Google Chrome** 登录了 `claude.ai` 和/或 `chatgpt.com`
- 有 Swift 工具链（Xcode 或 Command Line Tools，无需完整 Xcode）

## 构建 / 安装

```bash
./setup-signing.sh    # 首次：创建稳定自签名证书
./build.sh            # 编译 + 签名 → LimitHUD.app
./build.sh run        # 编译并启动
./build.sh install    # 编译 + 装到 /Applications 并启动
```

自签名证书让 app 身份跨重编译稳定，钥匙串「始终允许」一次后永久记住。

</details>
