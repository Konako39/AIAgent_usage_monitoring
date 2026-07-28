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
- 監測 Tibo（`@thsottiaux`）的新推文，可交由 OpenAI、Claude、Gemini 或 DeepSeek 判斷是否可能預示 GPT / Codex 額度重置。
- 支援透過 Base URL、選填 API Key 與動態模型清單連接自訂 OpenAI-compatible 介面。
- 在 GPT 任務下方顯示最新推文與簡短 AI 結論；可能重置時 GPT 卡片會變成綠色邊框，點擊一次即復原。
- 可為 Tibo 與 AI 流量啟用自訂 HTTP/Mixed 代理，預設填入 Clash 常見的 `127.0.0.1:7890`，連接埠可編輯並可測試連線。
- 位於 Finder 桌面層，一般應用程式視窗會蓋住它。
- 支援英語、簡體中文、繁體中文和日語。
- macOS 26 使用原生 Liquid Glass，舊系統使用原生視覺效果回退。

## 資料與隱私

GPT / Codex 額度來自本機 Codex 唯讀 app-server 介面。Claude 的 5 小時和本週資料來自 Claude Desktop 自己的本機額度歷史。應用程式不會讀取、複製或上傳 Claude Desktop 的工作階段 Cookie。

Fable 是模型專屬限制，Claude Desktop 可能不會將它寫入本機歷史。如果顯示 `—`，請在設定中點選「連線 Fable 額度」完成一次 Claude Code 官方授權。也可選擇使用 Anthropic Admin API Key 與自訂每月預算。

預設情況下，Tibo 監測只需公開主頁連結 `https://x.com/thsottiaux`，無需 X 開發者憑證。它會並行嘗試 X 公開主頁、公開嵌入時間軸和備用唯讀服務。當這些公開通道都無法使用時，仍可在進階選項中使用 X API Bearer Token。

可選擇 OpenAI、Claude、Gemini、DeepSeek 或自訂 OpenAI-compatible 介面，輸入必要的 API 資訊，測試連線以載入可用模型，再選擇模型。自訂介面可輸入 `https://api.example.com/v1` 這類 Base URL；LM Studio 等本機服務可使用 `http://localhost`。自動檢測每 2 分鐘執行一次，星光按鈕可立即重新分析最新推文。

在設定中輸入的憑證儲存於 macOS 鑰匙圈。開啟設定與測試公開主頁不會讀取已儲存的密鑰；只有你主動測試模型，或檢測到新推文需要 AI 分析時，才會存取鑰匙圈。後台檢測到推文沒有變化時也不會存取。額度歷史、最近三筆任務與最新 Tibo 分析只儲存在本機。只有新檢測到的 Tibo 推文文字會傳送給你選擇的 AI 服務商。

## 要求與建置

- macOS 14 或更高版本
- 本機已登入 ChatGPT / Codex 和 Claude Desktop / Claude Code
- 從原始碼建置需要 Swift 6 命令列工具

```bash
./build.sh
```

成品位於 `dist/Agent AI Usage.app`。

## 疑難排解

- GPT 未顯示：開啟 ChatGPT 或 Codex，確認已登入，然後按重新整理。
- Claude 未顯示：開啟一次 Claude Desktop，讓它更新本機額度歷史。
- Fable 未顯示：使用「設定 → 連線 Fable 額度」。
- Tibo 分析未顯示：在設定中測試公開主頁和 AI 模型，然後按星光按鈕。如果公開通道顯示連線失敗，請檢查網路、VPN 或代理，稍後重試，或改用官方 X API。
- Clash 已執行但 X 仍連線失敗：在 Tibo 設定中啟用自訂代理，保留 `127.0.0.1:7890` 或輸入 Clash 目前的 HTTP/Mixed 連接埠，先按「測試代理」，再按「測試公開主頁」。
- 小工具不見了：使用選單列項目「在此顯示器顯示小工具」。

## 授權條款

[PolyForm Noncommercial 1.0.0](LICENSE)：允許個人和其他非商業用途，不授權商業使用。

為什麼沒有其他的？因為我只訂閱了 GPT 和 Claude。
