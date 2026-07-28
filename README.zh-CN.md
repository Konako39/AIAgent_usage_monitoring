# Agent AI Usage

[English](README.md) | 简体中文 | [繁體中文](README.zh-CNF.md) | [日本語](README.ja.md)

一个原生 macOS 桌面小组件，用来同时监控 GPT / Codex 与 Claude 额度，不会遮挡正在使用的窗口。

![Agent AI Usage](docs/agent-ai-usage.png)

## 功能

- 在一个紧凑的原生组件里显示 GPT / Codex 和 Claude 额度。
- Claude 同时显示 5 小时、本周和 Fable 三项限制。
- 每 30 秒刷新并重新检测服务。
- 将额度变化归因到最近的 Codex 或 Claude 任务。
- 每家最多保留三条最近任务，Claude 会分别显示每个变化的额度窗口。
- 监测 Tibo（`@thsottiaux`）的新推文，可交给 OpenAI、Claude、Gemini 或 DeepSeek 判断是否可能预示 GPT / Codex 额度重置。
- 支持通过 Base URL、可选 API Key 和动态模型列表连接自定义 OpenAI-compatible 接口。
- 在 GPT 任务下方显示最新推文和简洁 AI 结论；可能重置时 GPT 卡片变为绿色边框，点击一次即复原。
- 位于 Finder 桌面层，普通应用窗口会盖住它。
- 支持英语、简体中文、繁体中文和日语。
- macOS 26 使用原生 Liquid Glass，旧系统使用原生视觉效果回退。

## 数据与隐私

GPT / Codex 额度来自本机 Codex 只读 app-server 接口。Claude 的 5 小时和本周数据来自 Claude Desktop 自己的本地额度历史。应用不会读取、复制或上传 Claude Desktop 的会话 Cookie。

Fable 是模型专属限制，Claude Desktop 可能不会将它写入本地历史。如果显示 `—`，请在设置中点击“连接 Fable 额度”完成一次 Claude Code 官方授权。也可选择使用 Anthropic Admin API Key 与自定义月预算。

默认情况下，Tibo 监测只需要公开主页链接 `https://x.com/thsottiaux`，无需 X 开发者凭证。它会并行尝试 X 的公开嵌入时间线和备用只读服务。当两条公开通道都不可用时，仍可在高级选项中使用 X API Bearer Token。

可选择 OpenAI、Claude、Gemini、DeepSeek 或自定义 OpenAI-compatible 接口，输入必要的 API 信息，测试连接以加载可用模型，然后选择模型。自定义接口可填写 `https://api.example.com/v1` 这样的 Base URL；LM Studio 等本机服务可使用 `http://localhost`。自动检测每 2 分钟执行一次，星光按钮可立即重新分析最新推文。

在设置中填入的凭证保存于 macOS 钥匙串。打开设置和测试公开主页不会读取已保存的密钥；只有你主动测试模型，或检测到新推文需要 AI 分析时，才会访问钥匙串。后台检测到推文没有变化时也不会访问。额度历史、最近三条任务和最新 Tibo 分析只保存在本机。只有新检测到的 Tibo 推文文本会发送给你选择的 AI 服务商。

## 要求与构建

- macOS 14 或更高版本
- 本机已登录 ChatGPT / Codex 和 Claude Desktop / Claude Code
- 从源码构建需要 Swift 6 命令行工具

```bash
./build.sh
```

成品位于 `dist/Agent AI Usage.app`。

## 故障排查

- GPT 未显示：打开 ChatGPT 或 Codex，确认已登录，然后点击刷新。
- Claude 未显示：打开一次 Claude Desktop，让它更新本地额度历史。
- Fable 未显示：使用“设置 → 连接 Fable 额度”。
- Tibo 分析未显示：在设置中测试公开主页和 AI 模型，然后点击星光按钮。如果两条公开通道都提示连接失败，请检查网络或 VPN，稍后重试，或改用官方 X API。
- 小组件不见了：使用菜单栏项“在此显示器显示小组件”。

## 许可证

[PolyForm Noncommercial 1.0.0](LICENSE)：允许个人和其他非商业用途，不授权商业使用。

为什么没有其他的？因为我只订阅了 GPT 和 Claude。
