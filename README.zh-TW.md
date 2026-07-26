# Agent AI Usage

[English](README.md) | [简体中文](README.zh-CN.md) | 繁體中文 | [日本語](README.ja.md)

一個原生 macOS 桌面小工具，用來同時監控 GPT / Codex 與 Claude 額度，不會擋住正在使用的視窗。

![Agent AI Usage](docs/agent-ai-usage.png)

## 功能

- 在一個緊湊的原生元件中顯示 GPT / Codex 和 Claude 額度。
- Claude 同時顯示 5 小時、本週和 Fable 三項限制。
- 每 30 秒重新整理並重新偵測服務。
- 將額度變化歸因到最近的 Codex 或 Claude 任務。
- 每個服務最多保留三筆最近任務，Claude 會分別顯示每個變化的額度視窗。
- 位於 Finder 桌面層，一般應用程式視窗會蓋住它。
- 支援英語、簡體中文、繁體中文和日語。
- macOS 26 使用原生 Liquid Glass，舊系統使用原生視覺效果回退。

## 資料與隱私

GPT / Codex 額度來自本機 Codex 唯讀 app-server 介面。Claude 的 5 小時和本週資料來自 Claude Desktop 自己的本機額度歷史。應用程式不會讀取、複製或上傳 Claude Desktop 的工作階段 Cookie。

Fable 是模型專屬限制，Claude Desktop 可能不會將它寫入本機歷史。如果顯示 `—`，請在設定中點選「連線 Fable 額度」完成一次 Claude Code 官方授權。也可選擇使用 Anthropic Admin API Key 與自訂每月預算。

在設定中輸入的憑證儲存於 macOS 鑰匙圈。額度歷史與最近三筆任務只儲存在本機。

## 要求與建置

- macOS 14 或更高版本
- 本機已登入 ChatGPT / Codex 和 Claude Desktop / Claude Code
- 從原始碼建置需要 Swift 6 命令列工具

```bash
./build.sh
```

成品位於 `dist/Agent AI Usage.app`。

## 授權條款

[PolyForm Noncommercial 1.0.0](LICENSE)：允許個人和其他非商業用途，不授權商業使用。

為什麼沒有其他的？因為我只訂閱了 GPT 和 Claude。
