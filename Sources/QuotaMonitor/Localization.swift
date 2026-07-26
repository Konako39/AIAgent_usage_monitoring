import Foundation

enum DemoMode {
    static let enabled = ProcessInfo.processInfo.arguments.contains("--demo")
}

enum AcceptanceMode {
    static let enabled = ProcessInfo.processInfo.arguments.contains("--acceptance")
        || ProcessInfo.processInfo.arguments.contains("--acceptance-live")
    static let includesLiveProviders = ProcessInfo.processInfo.arguments.contains("--acceptance-live")
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .english: return "en_US"
        case .simplifiedChinese: return "zh_CN"
        case .traditionalChinese: return "zh_TW"
        case .japanese: return "ja_JP"
        }
    }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .japanese: return "日本語"
        }
    }
}

enum L10n {
    static var currentLanguage: AppLanguage {
        if DemoMode.enabled { return .english }
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.english.rawValue
        return AppLanguage(rawValue: raw) ?? .english
    }

    static func text(_ key: String, language: AppLanguage? = nil) -> String {
        let selected = language ?? currentLanguage
        if selected == .traditionalChinese {
            return traditionalChineseTranslations[key]
                ?? translations[.simplifiedChinese]?[key]
                ?? translations[.english]?[key]
                ?? key
        }
        return translations[selected]?[key] ?? translations[.english]?[key] ?? key
    }

    private static let traditionalChineseTranslations: [String: String] = [
        "appName": "AI 額度監控",
        "settingsTitle": "AI 額度監控設定",
        "syncing": "正在同步…",
        "updatedFormat": "%@ 更新",
        "refresh": "立即重新整理",
        "settings": "設定…",
        "showWidget": "將元件顯示在目前螢幕",
        "quit": "結束 AI 額度監控",
        "notConnectedSettings": "從選單列開啟設定",
        "refreshFailed": "暫時無法重新整理",
        "codexConnecting": "正在連線 Codex…",
        "claudeNotConnected": "尚未連線 Claude",
        "codexNotFound": "找不到 Codex 登入",
        "malformedResponse": "無法讀取回傳的用量資料",
        "timedOut": "連線逾時",
        "weeklyLimit": "本週額度",
        "dailyLimit": "每日額度",
        "currentLimit": "目前額度",
        "resetAt": "重設於 %@",
        "codexConnected": "已連線 Codex",
        "claudeDesktopOpen": "開啟 Claude Desktop 後會自動顯示",
        "claudeAPIUsage": "Claude API 用量",
        "claudeExpired": "Claude 登入已失效，請重新登入",
        "threeLimits": "3 項限制",
        "localSecureSync": "Claude Desktop · 本機安全同步",
        "claudeConnected": "已連線 Claude",
        "apiBudgetRequired": "請設定 Claude API 每月預算",
        "apiKeyInvalid": "Claude Admin Key 無效或沒有權限",
        "apiBudgetUsed": "API 每月預算 · 已使用 $%@",
        "apiBudgetReset": "預算 $%@ · 下個月重設",
        "fiveHours": "5 小時",
        "thisWeek": "本週",
        "fable": "Fable",
        "codexConversation": "Codex 對話",
        "claudeConversation": "Claude 對話",
        "historyEmpty": "額度變化後會記錄任務",
        "recentTasks": "最近任務",
        "justNow": "剛剛",
        "helpTooltip": "沒有顯示額度？",
        "helpTitle": "額度沒有顯示嗎？",
        "helpIntro": "應用程式每 30 秒重新偵測兩個服務，無需重新啟動元件。",
        "helpGPT": "GPT / Codex：開啟 ChatGPT 或 Codex 並確認已登入，然後點選重新整理。",
        "helpClaude": "Claude：至少開啟一次 Claude Desktop，讓它更新本機額度歷史。",
        "helpFable": "Fable：若顯示「—」，請在設定中點選「連線 Fable 額度」完成一次官方授權。",
        "statusReady": "已連線",
        "statusWaiting": "等待連線",
        "displaySection": "顯示",
        "language": "語言",
        "desktopWidgetMode": "桌面小工具模式",
        "desktopWidgetDescription": "元件位於一般應用程式視窗下方，不會擋住操作。",
        "codexSection": "GPT · Codex",
        "codexDetected": "已使用本機 Codex 登入",
        "codexUndetected": "未偵測到 Codex 登入",
        "codexDescription": "無需重複輸入密碼；透過本機 Codex 唯讀介面取得每週額度。",
        "claudeSection": "Claude 訂閱",
        "claudeDetected": "已連線 Claude Desktop / Claude Code",
        "claudeUndetected": "未偵測到 Claude 額度",
        "claudePrivacy": "優先讀取 Claude Desktop 自己的額度歷史；不讀取、複製或上傳桌面工作階段 Cookie。",
        "oauthPlaceholder": "Claude OAuth Access Token（選填）",
        "saveSubscription": "儲存訂閱登入",
        "connectFable": "連線 Fable 額度",
        "openClaude": "開啟 Claude",
        "claudeHelp": "5 小時和本週直接來自 Claude Desktop。Fable 若顯示「—」，請完成一次授權。",
        "savedClaude": "Claude 登入已安全儲存至鑰匙圈",
        "finishTerminalLogin": "請在終端機完成 Claude 登入，然後重新整理元件",
        "claudeCodeMissing": "找不到 Claude Code",
        "apiFallbackSection": "Claude API 備用模式",
        "monthlyBudget": "每月預算（USD）",
        "saveAPI": "儲存 API 設定",
        "savedAPI": "API 設定已安全儲存至鑰匙圈",
        "apiFallbackHelp": "僅在沒有 Claude 訂閱登入時使用；將官方組織 API 費用與自訂每月預算比較。",
        "primary": "額度"
    ]

    private static let translations: [AppLanguage: [String: String]] = [
        .english: [
            "appName": "Agent AI Usage",
            "settingsTitle": "Agent AI Usage Settings",
            "syncing": "Syncing…",
            "updatedFormat": "Updated %@",
            "refresh": "Refresh now",
            "settings": "Settings…",
            "showWidget": "Show widget on this display",
            "quit": "Quit Agent AI Usage",
            "notConnectedSettings": "Open Settings from the menu bar",
            "refreshFailed": "Unable to refresh",
            "codexConnecting": "Connecting to Codex…",
            "claudeNotConnected": "Claude is not connected",
            "codexNotFound": "Codex sign-in not found",
            "malformedResponse": "The usage response could not be read",
            "timedOut": "Connection timed out",
            "weeklyLimit": "Weekly limit",
            "dailyLimit": "Daily limit",
            "currentLimit": "Current limit",
            "resetAt": "Resets %@",
            "codexConnected": "Connected to Codex",
            "claudeDesktopOpen": "Open Claude Desktop to show usage",
            "claudeAPIUsage": "Claude API usage",
            "claudeExpired": "Claude sign-in expired. Please sign in again.",
            "threeLimits": "3 limits",
            "localSecureSync": "Claude Desktop · secure local sync",
            "claudeConnected": "Connected to Claude",
            "apiBudgetRequired": "Set a monthly Claude API budget",
            "apiKeyInvalid": "Claude Admin Key is invalid or lacks permission",
            "apiBudgetUsed": "API monthly budget · $%@ used",
            "apiBudgetReset": "$%@ budget · resets next month",
            "fiveHours": "5 hours",
            "thisWeek": "Weekly",
            "fable": "Fable",
            "codexConversation": "Codex conversation",
            "claudeConversation": "Claude conversation",
            "historyEmpty": "Tasks appear after usage changes",
            "recentTasks": "Recent tasks",
            "justNow": "just now",
            "helpTooltip": "Usage not showing?",
            "helpTitle": "Usage not showing?",
            "helpIntro": "Both providers are detected again every 30 seconds. You never need to restart the widget.",
            "helpGPT": "GPT / Codex: open ChatGPT or Codex and make sure you are signed in, then press Refresh.",
            "helpClaude": "Claude: open Claude Desktop once so it can update its local usage history.",
            "helpFable": "Fable: if it shows —, use Connect Fable usage in Settings for a one-time official authorization.",
            "statusReady": "Ready",
            "statusWaiting": "Waiting",
            "displaySection": "Display",
            "language": "Language",
            "desktopWidgetMode": "Desktop widget mode",
            "desktopWidgetDescription": "The widget stays behind normal app windows, so it never blocks your work.",
            "codexSection": "GPT · Codex",
            "codexDetected": "Using the local Codex sign-in",
            "codexUndetected": "Codex sign-in not detected",
            "codexDescription": "No password is requested. Weekly usage is read through the local Codex read-only interface.",
            "claudeSection": "Claude subscription",
            "claudeDetected": "Connected to Claude Desktop / Claude Code",
            "claudeUndetected": "Claude usage not detected",
            "claudePrivacy": "Claude Desktop's own usage history is preferred. Your desktop session cookies are never read, copied, or uploaded.",
            "oauthPlaceholder": "Claude OAuth access token (optional)",
            "saveSubscription": "Save subscription sign-in",
            "connectFable": "Connect Fable usage",
            "openClaude": "Open Claude",
            "claudeHelp": "5-hour and weekly limits come directly from Claude Desktop. If Fable shows —, use Connect Fable usage for one-time authorization.",
            "savedClaude": "Claude sign-in saved securely in Keychain",
            "finishTerminalLogin": "Finish Claude sign-in in Terminal, then refresh the widget",
            "claudeCodeMissing": "Claude Code was not found",
            "apiFallbackSection": "Claude API fallback",
            "monthlyBudget": "Monthly budget (USD)",
            "saveAPI": "Save API settings",
            "savedAPI": "API settings saved securely in Keychain",
            "apiFallbackHelp": "Used only without a Claude subscription sign-in. It compares official organization API spend with your custom monthly budget.",
            "primary": "Limit",
            "demoGPTTask1": "Refine onboarding flow",
            "demoGPTTask2": "Review authentication tests",
            "demoClaudeTask1": "Design analytics dashboard",
            "demoClaudeTask2": "Fix project search latency"
        ],
        .simplifiedChinese: [
            "appName": "AI 额度监控",
            "settingsTitle": "AI 额度监控设置",
            "syncing": "正在同步…",
            "updatedFormat": "%@ 更新",
            "refresh": "立即刷新",
            "settings": "设置…",
            "showWidget": "显示组件到当前屏幕",
            "quit": "退出 AI 额度监控",
            "notConnectedSettings": "从菜单栏打开设置",
            "refreshFailed": "暂时无法刷新",
            "codexConnecting": "正在连接 Codex…",
            "claudeNotConnected": "尚未连接 Claude",
            "codexNotFound": "未找到 Codex 登录",
            "malformedResponse": "返回数据无法识别",
            "timedOut": "连接超时",
            "weeklyLimit": "本周额度",
            "dailyLimit": "每日额度",
            "currentLimit": "当前额度",
            "resetAt": "重置于 %@",
            "codexConnected": "已连接 Codex",
            "claudeDesktopOpen": "打开 Claude Desktop 后自动显示",
            "claudeAPIUsage": "Claude API 使用",
            "claudeExpired": "Claude 登录已失效，请重新登录",
            "threeLimits": "3 项限制",
            "localSecureSync": "Claude Desktop · 本机安全同步",
            "claudeConnected": "已连接 Claude",
            "apiBudgetRequired": "请设置 Claude API 月预算",
            "apiKeyInvalid": "Claude Admin Key 无效或无权限",
            "apiBudgetUsed": "API 月预算 · 已用 $%@",
            "apiBudgetReset": "预算 $%@ · 下月重置",
            "fiveHours": "5 小时",
            "thisWeek": "本周",
            "fable": "Fable",
            "codexConversation": "Codex 对话",
            "claudeConversation": "Claude 对话",
            "historyEmpty": "额度变化后将记录任务",
            "recentTasks": "最近任务",
            "justNow": "刚刚",
            "helpTooltip": "没有显示额度？",
            "helpTitle": "额度没显示怎么办？",
            "helpIntro": "应用每 30 秒重新检测两家服务，无需重启组件。",
            "helpGPT": "GPT / Codex：打开 ChatGPT 或 Codex 并确认已登录，然后点击刷新。",
            "helpClaude": "Claude：至少打开一次 Claude Desktop，让它更新本地额度历史。",
            "helpFable": "Fable：若显示“—”，在设置里点击“连接 Fable 额度”完成一次官方授权。",
            "statusReady": "已连接",
            "statusWaiting": "等待连接",
            "displaySection": "显示",
            "language": "语言",
            "desktopWidgetMode": "桌面小组件模式",
            "desktopWidgetDescription": "组件位于普通应用窗口下方，不会遮挡操作。",
            "codexSection": "GPT · Codex",
            "codexDetected": "已使用本机 Codex 登录",
            "codexUndetected": "未检测到 Codex 登录",
            "codexDescription": "无需重复输入密码；通过本机 Codex 只读接口获取周额度。",
            "claudeSection": "Claude 订阅",
            "claudeDetected": "已连接 Claude Desktop / Claude Code",
            "claudeUndetected": "未检测到 Claude 额度",
            "claudePrivacy": "优先读取 Claude Desktop 自己的额度历史；不读取、复制或上传桌面会话 Cookie。",
            "oauthPlaceholder": "Claude OAuth Access Token（可选）",
            "saveSubscription": "保存订阅登录",
            "connectFable": "连接 Fable 额度",
            "openClaude": "打开 Claude",
            "claudeHelp": "5 小时和本周直接来自 Claude Desktop。Fable 若显示“—”，请完成一次授权。",
            "savedClaude": "Claude 登录已安全保存到钥匙串",
            "finishTerminalLogin": "请在终端完成 Claude 登录，然后刷新组件",
            "claudeCodeMissing": "未找到 Claude Code",
            "apiFallbackSection": "Claude API 备用模式",
            "monthlyBudget": "月预算（USD）",
            "saveAPI": "保存 API 设置",
            "savedAPI": "API 设置已安全保存到钥匙串",
            "apiFallbackHelp": "仅在没有 Claude 订阅登录时使用；将官方组织 API 花费与自定义月预算对比。",
            "primary": "额度"
        ],
        .japanese: [
            "appName": "AI 使用量",
            "settingsTitle": "AI 使用量の設定",
            "syncing": "同期中…",
            "updatedFormat": "%@ 更新",
            "refresh": "今すぐ更新",
            "settings": "設定…",
            "showWidget": "このディスプレイに表示",
            "quit": "AI 使用量を終了",
            "notConnectedSettings": "メニューバーから設定を開いてください",
            "refreshFailed": "更新できません",
            "codexConnecting": "Codex に接続中…",
            "claudeNotConnected": "Claude は未接続です",
            "codexNotFound": "Codex のログインが見つかりません",
            "malformedResponse": "使用量データを読み取れません",
            "timedOut": "接続がタイムアウトしました",
            "weeklyLimit": "週間上限",
            "dailyLimit": "1 日の上限",
            "currentLimit": "現在の上限",
            "resetAt": "%@ にリセット",
            "codexConnected": "Codex に接続済み",
            "claudeDesktopOpen": "Claude Desktop を開くと表示されます",
            "claudeAPIUsage": "Claude API 使用量",
            "claudeExpired": "Claude のログインが無効です。再ログインしてください",
            "threeLimits": "3 つの上限",
            "localSecureSync": "Claude Desktop · 安全なローカル同期",
            "claudeConnected": "Claude に接続済み",
            "apiBudgetRequired": "Claude API の月間予算を設定してください",
            "apiKeyInvalid": "Claude Admin Key が無効か権限がありません",
            "apiBudgetUsed": "API 月間予算 · $%@ 使用済み",
            "apiBudgetReset": "予算 $%@ · 翌月リセット",
            "fiveHours": "5 時間",
            "thisWeek": "週間",
            "fable": "Fable",
            "codexConversation": "Codex の会話",
            "claudeConversation": "Claude の会話",
            "historyEmpty": "使用量が変わるとタスクを記録します",
            "recentTasks": "最近のタスク",
            "justNow": "たった今",
            "helpTooltip": "使用量が表示されない場合",
            "helpTitle": "使用量が表示されませんか？",
            "helpIntro": "2 つのプロバイダーは 30 秒ごとに再検出されます。ウィジェットの再起動は不要です。",
            "helpGPT": "GPT / Codex：ChatGPT または Codex を開き、ログインを確認してから更新します。",
            "helpClaude": "Claude：Claude Desktop を一度開き、ローカルの使用量履歴を更新します。",
            "helpFable": "Fable：— の場合は、設定の「Fable 使用量を接続」で一度だけ公式認証を行います。",
            "statusReady": "接続済み",
            "statusWaiting": "接続待ち",
            "displaySection": "表示",
            "language": "言語",
            "desktopWidgetMode": "デスクトップウィジェット",
            "desktopWidgetDescription": "通常のアプリウィンドウの背面に表示され、作業を妨げません。",
            "codexSection": "GPT · Codex",
            "codexDetected": "ローカルの Codex ログインを使用中",
            "codexUndetected": "Codex ログインを検出できません",
            "codexDescription": "パスワードは不要です。ローカル Codex の読み取り専用インターフェースから週間使用量を取得します。",
            "claudeSection": "Claude サブスクリプション",
            "claudeDetected": "Claude Desktop / Claude Code に接続済み",
            "claudeUndetected": "Claude 使用量を検出できません",
            "claudePrivacy": "Claude Desktop 自身の使用量履歴を優先します。セッション Cookie は読み取り・コピー・送信しません。",
            "oauthPlaceholder": "Claude OAuth アクセストークン（任意）",
            "saveSubscription": "サブスクリプションを保存",
            "connectFable": "Fable 使用量を接続",
            "openClaude": "Claude を開く",
            "claudeHelp": "5 時間と週間の上限は Claude Desktop から取得します。Fable が — の場合は一度だけ認証します。",
            "savedClaude": "Claude ログインをキーチェーンに安全に保存しました",
            "finishTerminalLogin": "ターミナルで Claude ログインを完了し、ウィジェットを更新してください",
            "claudeCodeMissing": "Claude Code が見つかりません",
            "apiFallbackSection": "Claude API フォールバック",
            "monthlyBudget": "月間予算（USD）",
            "saveAPI": "API 設定を保存",
            "savedAPI": "API 設定をキーチェーンに安全に保存しました",
            "apiFallbackHelp": "Claude サブスクリプションがない場合のみ使用し、公式 API 費用と月間予算を比較します。",
            "primary": "上限"
        ]
    ]
}

@inline(__always)
func T(_ key: String, language: AppLanguage? = nil) -> String {
    L10n.text(key, language: language)
}
