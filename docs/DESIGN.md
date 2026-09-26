# AFM Chat 設計

> English summary: A small native macOS app for local Apple Foundation Models,
> with image input, automatic context compaction, JSONL transcripts and a
> rebuildable SQLite index. Users build and sign their own copy.

## 已確認範圍

- SwiftUI 單視窗，先供作者使用，也讓其他人 clone 後自行建置與簽名。
- 文字、多輪對話、每次單張圖片（貼上／拖入／選取）、串流與停止。
- 接近實際模型上下文上限時自動摘要舊對話，保留近期原文。
- 整理中顯示狀態，完成後留下標記；整理失敗不可靜默丟棄歷史。
- 完整對話即時以 JSONL 留存；SQLite 只是對話清單與搜尋索引。
- 使用者訊息送出時保存；回答在完成、停止、可處理錯誤時保存。
  程序閃退不保證保留尚未完成的串流內容。
- 對話可新增、切換、重新命名、刪除；圖片留在本機資料目錄。
- 無 PCC、雲端 fallback、代理工具呼叫、OpenAI 相容伺服器或帳號系統。

## 實作邊界

`Sources/AFMChatCore` 負責事件、儲存與推論；`app/AFMChat` 負責 SwiftUI。
測試使用隔離資料夾，合成模型測試與原生模型實測分別回報。
新 API 包含圖片輸入與 token 計數，第一版要求 macOS 27 與 Xcode 27。
模型名稱、可用性及上下文大小由框架即時取得，不硬編為特定晶片型號。

## 驗證與邊界

- Swift Task 收到文字後取消，後續原生請求已成功；服務內部資源釋放未觀測。
- 合成對話已觸發自動整理與正常續答；長期摘要品質未建立統計。
- 圖片推論通過，框架圖片計數失敗，改用文字精確計數與圖片估算額度。
- JSONL 中斷寫入、索引重建與超大輸入恢復有自動測試，GUI 重開已驗證。

詳見 [驗證紀錄](VERIFICATION.md)。
