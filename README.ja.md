# Agent AI Usage

[English](README.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-CNF.md) | 日本語

GPT / Codex と Claude の使用量を同時に監視する、macOS ネイティブのデスクトップウィジェットです。通常のアプリウィンドウの背面に表示されます。

![Agent AI Usage](docs/agent-ai-usage.png)

## 機能

- GPT / Codex と Claude の使用量を 1 つのコンパクトなネイティブウィジェットに表示。
- Claude の 5 時間、週間、Fable の 3 つの上限を同時に表示。
- 30 秒ごとに更新し、サービスを再検出。
- 使用量の変化を最近の Codex または Claude タスクに関連付け。
- 各サービスで最大 3 件の最近タスクを保存し、Claude は変化した各使用量ウィンドウを個別に表示。
- Tibo（`@thsottiaux`）の新しいポストを監視し、OpenAI、Claude、Gemini、DeepSeek のいずれかで GPT / Codex 使用量のリセットを示唆するか判定。
- GPT タスクの下に最新ポストと簡潔な AI 判定を表示。リセットの可能性があると GPT カードが緑色になり、1 回クリックすると元に戻ります。
- Finder のデスクトップレベルに配置され、通常のアプリウィンドウの背面に表示。
- 英語、簡体中国語、繁体中国語、日本語に対応。
- macOS 26 ではネイティブ Liquid Glass、以前のシステムではネイティブ視覚効果のフォールバックを使用。

## データとプライバシー

GPT / Codex はローカル Codex の読み取り専用 app-server インターフェースから取得します。Claude の 5 時間と週間データは Claude Desktop 自身のローカル使用量履歴から読み取ります。Claude Desktop のセッション Cookie は読み取り・コピー・送信しません。

Fable はモデル固有の上限で、Claude Desktop がローカル履歴に保存しない場合があります。`—` の場合は、設定の「Fable 使用量を接続」で一度だけ Claude Code 公式認証を行います。

Tibo 監視は X の公式 API を使用するため、X API Bearer Token が必要です。設定でその Token を入力し、OpenAI、Claude、Gemini、DeepSeek から選択して対応する API Key を追加し、接続テストで利用可能なモデルを取得してから 1 つ選択します。自動確認は 2 分ごとに実行され、更新ボタン横のスパークルボタンで最新ポストをすぐに再解析できます。

設定で入力した認証情報は macOS キーチェーンに保存されます。使用量履歴、最近 3 件のタスク、最新の Tibo 分析は Mac 内にのみ保存され、新しく検出された Tibo のポスト本文だけが選択した AI プロバイダーに送信されます。

## 要件とビルド

- macOS 14 以降
- ChatGPT / Codex と Claude Desktop / Claude Code にローカルでログイン済み
- ソースからのビルドに Swift 6 Command Line Tools

```bash
./build.sh
```

アプリは `dist/Agent AI Usage.app` に生成されます。

## ライセンス

[PolyForm Noncommercial 1.0.0](LICENSE)。個人およびその他の非商用利用は許可されますが、商用利用は許諾されません。

なぜ他のプロバイダーがないのですか？私が契約しているのは GPT と Claude だけだからです。
