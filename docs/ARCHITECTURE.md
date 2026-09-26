# 架構

> English summary: SwiftUI calls a single generation coordinator. JSONL is authoritative,
> SQLite is a disposable projection, and Apple's on-device model handles inference.
> No backend service or agent runtime is involved.

## 目錄

| 路徑 | 職責 |
|---|---|
| `app/AFMChat/` | SwiftUI 視窗、AppKit 輸入框、圖片輸入、正常離開時保存 |
| `Sources/AFMChatCore/` | 模型、對話事件、儲存、索引、生成狀態機 |
| `Sources/CSQLite/` | 系統 SQLite 模組橋接 |
| `Tests/AFMChatCoreTests/` | 隔離儲存與可重現的假模型測試 |
| `tools/AFMChatProbe/` | 原生模型文字、圖片、compact 整合驗證 |
| `scripts/` | 建置與原生取消探針 |
| `kc_afm_chat.xcodeproj/` | 可直接開啟的 App project 與 shared scheme |

UI → `ChatCoordinator` → `ConversationStore` / `ChatModel`。
`AppleModel` 實作 `ChatModel`，直接呼叫 `SystemLanguageModel.default`。
Swift Package 與 App 共用同一份核心程式，沒有第三方套件依賴。

## 回合與 compact

狀態順序是 idle → preparing → compacting（需要時）→ generating → idle。
stopping 會取消同一個 Swift Task，等它結束後才回 idle。90 秒看門狗也走這條路；
它是取消要求，不保證 Apple 服務在固定時間內終止。

文字輸入以框架 tokenCount 計算。macOS 27.0 build 26A428 的圖片計數可重現錯誤
1001，但同圖推論成功，故圖片一張額外預留 **1,536 tokens**。這是應用層保守策略，
不是量得的圖片 token 數或上界保證。介面顯示「輸入預算約」。

回答空間 `min(768, max(128, contextSize / 5))`，另留 128 token 餘裕。
若輸入預算超過其餘空間，以純文字摘要較舊回合，盡量保留最近一輪；仍不足則把
保留輪次一併摘要。摘要生成上限 384 tokens，輸入按框架計數分批，使用 greedy。
只有摘要生成成功、後續輸入預算通過且未取消時，才追加 compactionCompleted。
原始訊息仍在 JSONL，摘要不改寫歷史。

摘要是一般文字生成，避免將自由中文長欄位交給結構化輸出。過長單則訊息會被拒絕，
失敗回合保留於歷史、排除於後續模型脈絡。App 沒有在背景建立第二個 agent loop。

## 儲存與規模

每次事件同步追加 JSONL，成功後更新記憶體狀態與 SQLite。索引失敗不把已保存事件
當成失敗重送。啟動重播所有對話並重建索引，因此第一版適合小量本機聊天；大量
長年歷史可能延長啟動與索引時間，沒有宣稱可處理任意規模。

SQLite FTS5 表保存文字，但查詢目前採 escaped LIKE，提供中英文片段搜尋，
不是語意搜尋。完整資料契約見 [DATA_FORMAT.md](DATA_FORMAT.md)。

## 參考與取捨

- [Codex rollout policy](https://github.com/openai/codex/blob/25270df2615eb4da5b9d4a9a392226933fb096c5/codex-rs/rollout/src/policy.rs)：訊息完成與 delta 的保存政策不同。
- [Codex history materialization](https://github.com/openai/codex/blob/25270df2615eb4da5b9d4a9a392226933fb096c5/codex-rs/thread-store/src/local/thread_history_materialization.rs)：JSONL 與 SQLite 投影。
- [Claude session browser](https://platform.claude.com/cookbook/claude-agent-sdk-05-building-a-session-browser)：每段對話 JSONL 與清單讀取。
- [Hermes storage](https://github.com/NousResearch/hermes-agent/blob/aae6c2044e3551207af57fceb7af94c4316373f9/website/docs/developer-guide/session-storage.md)：以 SQLite 為權威資料的另一種做法。

以上查閱於 2026-09-26。本程式選 JSONL 權威資料，方便檢視與恢復；不宣稱複製
Codex 或 Claude 的完整內部設計。公開文件及自行簽名流程參考
[Wherebear](https://github.com/KerberosClaw/kc_wherebear_oss) 與
[locationspoof](https://github.com/KerberosClaw/kc_locationspoof_oss) 的組織方式，維持單一 repo。
