# AFM Chat

> English summary: Maintain a small native on-device chat app. Preserve authoritative
> JSONL history, verify with synthetic data, and review public content before publishing.

先讀 README.md 與 docs/DESIGN.md。此專案為單一公開 repo。

- 維持小型本機聊天工具範圍，沒有雲端 fallback、代理工具或 API server。
- JSONL 為權威資料，SQLite 僅為可重建的投影。
- Compact 只改變模型脈絡，不刪除原始紀錄。
- 原生 Apple Intelligence 驗證與假模型單元測試分開回報。
- 使用合成測資及隔離資料目錄，不接觸使用者的 App 資料。
- 不提交真實對話、使用者圖片、個人路徑、主機名、簽名身分或 Team ID。
- README.md 英文與 README_zh.md 正體中文內容同步；技術文件用正體中文及短英文摘要。
- 執行 `swift test` 與 `scripts/build.sh`；原生模型探針需明確選用。
- Commit 使用 `feat:`、`fix:`、`docs:`、`chore:`。提交前完成驗證及公開內容審查，
  commit / push 前通知使用者，並遵守當次工作已有授權。
