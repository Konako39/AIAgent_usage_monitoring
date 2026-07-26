# Agent AI Usage

[English](README.md) | [简体中文](README.zh-CN.md) | 日本語

GPT / Codex と Claude の使用量を同時に監視する、macOS ネイティブのデスクトップウィジェットです。通常のアプリウィンドウの背面に表示されます。

![シミュレーションデータを使用した Agent AI Usage](docs/agent-ai-usage.png)

> スクリーンショットは分離されたデモモードで生成されています。タスク名とパーセントはすべて架空で、デスクトップやアカウントデータは含まれません。

## 機能

- GPT / Codex と Claude を 1 つのコンパクトなウィジェットに表示。
- Claude の 5 時間、週間、Fable の上限を同時に表示。
- 残量が多いと緑、少ないと赤に変化。
- 30 秒ごとに更新し、起動後にログインした場合もアプリの再起動は不要。
- 使用量の変化を最近の Codex / Claude タスクに関連付け。
- 各プロバイダー最大 3 件の最近タスクを保存し、Claude は変化した上限を個別に表示。
- Finder のデスクトップレベルに配置され、通常のウィンドウを妨げません。
- 更新ボタンの左側にトラブルシューティング説明。
- 英語、簡体中国語、日本語に対応。デフォルトは英語。
- macOS 26 では Liquid Glass、以前のシステムではネイティブの視覚効果を使用。

## データとプライバシー

GPT / Codex はローカル Codex の読み取り専用 app-server インターフェースから取得します。Claude の 5 時間と週間データは Claude Desktop 自身のローカル使用量履歴から読み取ります。Claude Desktop のセッション Cookie は読み取り・コピー・送信しません。

Fable はモデル固有の上限で、Claude Desktop がローカル履歴に保存しない場合があります。`—` の場合は、設定の「Fable 使用量を接続」で一度だけ Claude Code 公式認証を行います。

設定で入力した認証情報は macOS キーチェーンに保存され、使用量履歴と最近 3 件のタスクは Mac 内にのみ保存されます。

## 要件とビルド

- macOS 14 以降
- ChatGPT / Codex と Claude Desktop / Claude Code にローカルでログイン済み
- ソースからのビルドに Swift 6 Command Line Tools

```bash
./build.sh
```

アプリは `dist/Agent AI Usage.app` に生成されます。

## 受け入れチェック

```bash
.build/release/QuotaMonitor --acceptance
.build/release/QuotaMonitor --acceptance-live
```

このリリースは、GPT / Codex と Claude の実際のコールドスタート読み取りを含む 14 項目すべてに合格しています。

## ライセンス

[PolyForm Noncommercial 1.0.0](LICENSE)。個人およびその他の非商用利用は許可されますが、商用利用は許諾されません。
