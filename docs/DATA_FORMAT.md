# 資料格式與恢復

> English summary: Versioned, append-only JSONL events are authoritative. SQLite can
> be rebuilt. Complete corrupt records are preserved; a truncated final record is
> isolated before recovery. Back up the whole data directory with the app closed.

## 檔案配置

```text
AFMChat/
  writer.lock
  index.sqlite                  # 及 SQLite 的 wal/shm 暫存檔
  conversations/<UUID>/
    events.jsonl
    attachments/<UUID>.<extension>
    partial-<UUID>.recovery      # 僅在尾端寫入中斷時出現
```

JSONL 每行一個 UTF-8 JSON，以換行結尾。每筆都有 `version: 1`、UUID `id`、
對話內連續 `sequence`（從 1 起）、ISO 8601 `timestamp` 與 `kind`。

| kind | 內容 |
|---|---|
| created / renamed | `text`：標題 |
| message | `message`：id、role、text、可選 imagePath、status、createdAt |
| generationStarted / generationEnded | 開始／結束；結束的 `text` 為狀態 |
| compactionStarted / compactionFailed | 開始／失敗；失敗可帶 `text` 原因 |
| compactionCompleted | `compaction`：summary、throughMessageID、sourceMessageCount、inputTokensAfter |

`role` 為 user / assistant；`status` 為 complete / stopped / failed。
圖片路徑只能是對話目錄內的 `attachments/<filename>`，拒絕跨目錄及逃逸 symlink。
`throughMessageID` 指摘要取代的最後一筆模型脈絡；此前原文仍可顯示與搜尋。
`inputTokensAfter` 是這次整理後的輸入預算，含圖時為估算；`sourceMessageCount`
為本次新涵蓋的訊息數，不是整段對話累計數。

## 一致性

先將 JSONL 追加並 synchronize，再更新 SQLite。SQLite 更新失敗會停用投影，
改用記憶體搜尋並顯示警告；不重送已保存事件。啟動時以 JSONL 重建索引。
同一資料夾用程序鎖確保單一寫入者。此格式第一版沒有跨裝置同步或合併契約。

保存粒度是訊息，不是串流 delta。發生無法處理的崩潰時，已完成的事件保留；
尚未寫入的回答片段可能消失。有 generationStarted 而沒有 generationEnded 時，
重開顯示中斷提示，不自動重播請求。

## 恢復

先關閉 App 並複製整個資料夾。若只有索引壞掉，可移走 `index.sqlite` 與對應的
`-wal`、`-shm`，再啟動重建。App 也會在可辨識的索引損壞時保留舊檔後重建。

JSONL 只有最後一筆未完整寫入時，先確認之前每一筆有效，再保存尾端為 `.recovery`，
保留完整行重新啟動。有效但缺少最後換行的紀錄會補換行。完整行損壞、未知版本或
序號不連續時，該對話會暫時隱藏並顯示警告，原檔不改寫。修復前應保留備份，
不要用刪除整行的方式盲目處理未知版本。

刪除對話會移出可重播的 conversations 目錄再刪掉目錄及圖片，並重建索引。
若磁碟刪除失敗，會留下 `deleted-<UUID>` 資料夾及警告，需關閉 App 後手動處理。
刪除不代表磁碟安全抹除，也不刪除使用者自行建立的備份。
