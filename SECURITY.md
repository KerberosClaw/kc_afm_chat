# 安全與隱私

> English summary: Chats and images stay in a local plaintext data directory. The app
> calls the on-device model, has no telemetry or cloud fallback, and executes no model
> tools. This build is not sandboxed, encrypted by the app, notarized, or remotely synced.

App 只呼叫 `SystemLanguageModel.default`，沒有 PCC、網路供應商、HTTP server、
更新檢查、遙測或工具執行。模型回覆中的程式碼不會自動執行。Apple 系統下載模型、
系統診斷或使用者自行設定的備份不在 App 控制範圍。

對話、摘要、圖片及 SQLite 索引皆為本機明文。新資料目錄設為 700，JSONL 與圖片
設為 600；同一帳號及系統管理員仍可讀取。本機簽名版本沒有 App Sandbox，
權限邊界是 macOS 使用者權限。需要資料保護時請使用系統磁碟加密及適當帳號權限。

索引可重建，備份應包含 JSONL 與 attachments。圖片保留原始檔時也會保留 metadata。
App 不會主動去除 EXIF。刪除對話會清除使用中的資料，不保證物理磁碟抹除、
已備份資料消失或 SQLite 空白頁內容不可恢復。

不要在公開 issue 附上真實對話、圖片、SQLite 或完整資料夾。若需回報問題，
先用合成內容重現，提供 OS / Xcode 版本、模型名稱、去識別化錯誤及操作步驟。
發現可能洩露資料的漏洞時，請使用 GitHub repository 的私人漏洞回報功能（若已啟用）；
未啟用時先開一個不含利用細節或個資的 issue 請維護者提供聯絡方式。
