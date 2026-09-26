# 驗證紀錄

> English summary: The initial build was checked on an M1 Mac with native text/image
> inference, automatic compaction, cancellation and GUI persistence. Core tests use a
> fake model. These checks do not establish model accuracy or long-term summary quality.

## 環境

2026-09-26：Apple M1、8 GB、macOS 27.0 build 26A428、Xcode 27.0 build 27A266a、
Swift 6.4。框架回報 AFM 3 Core，contextSize 4096。

## 已驗證

| 檢查 | 結果 |
|---|---|
| `scripts/build.sh` | Release App 建置成功，ad-hoc 簽名與 strict verify 通過 |
| `swift test` | 11 項核心測試：重播、索引重建、中文搜尋、尾端中斷、完整行損壞、單一寫入者、路徑限制、compact、取消、超大輸入後恢復等 |
| `swift run AFMChatProbe <new-directory>` | 原生文字、合成圖片、自動整理與完整原文保留通過 |
| 文字 | 二加三回答五，單次約 3.72 秒 |
| 圖片 | 合成紅圓、藍方塊描述正確，單次約 8.34 秒 |
| Compact | 54 則合成歷史、3296 token 輸入預算觸發，自動整理加回答約 14.01 秒；名稱、日期、預算回答正確 |
| GUI | 整理中狀態、完成標記、原生圖片選取與預覽、剪貼簿圖片貼上、圖片回答、停止並保存部分文字、中文搜尋、重新命名、新增／切換對話 |
| 重開 App | 自訂標題、圖片、已停止的部分回覆恢復 |
| 原生取消探針 | 收到 13 個字後取消，Task 約 0.0003 秒返回；後續短問答約 2.61 秒 |

這些耗時是單次應用觀察，不是模型吞吐 benchmark。Compact 案例的近期原文也
包含相同事實，不能用它推定摘要本身的事實保留率。取消只觀測到客戶端與後續
請求成功，沒有量到服務內部資源何時釋放。

## 已知限制

- 同一張 PNG 的 Transcript / Prompt tokenCount 都回框架錯誤 1001，直接推論
  兩次成功。每張圖的 1536 token 是應用預算，不是實測上限。
- 無跨裝置同步、逐 token 耐久保存、資料加密、語意搜尋或發布用公證安裝包。
- 90 秒逾時會要求取消，但底層若不合作，App 仍需等待；不會啟動平行請求掩蓋卡住。
- 沒有對所有 Apple Silicon、OS 版本、圖片格式、輸入法或長期多次摘要建立測試矩陣。
- 拖放接收已實作，但此輪 GUI 驗證未操作跨視窗拖放；刪除的儲存路徑有核心測試，
  GUI 確認對話框未完成逐項操作覆蓋。
- 本次 Xcode 額外回報 CoreDevice / Simulator 外掛版本警告；macOS App 建置成功，
  沒有宣稱 iOS / Simulator 可用。本專案沒有 iOS target。
- 尚未配置雲端 CI；上述為實機本機驗證，不把 workflow 存在等同於驗證通過。

## 重做

先照 [INSTALL](INSTALL.md) 建置，再執行 README 的測試指令。原生探針產生一張
合成圖片與隔離 JSONL 資料；不要將輸出整包提交進 repo。GUI 驗證可把
`AFM_CHAT_DATA_DIR` 指向探針輸出，使用 `UI compact verification` 對話送出下一句，
檢查整理中狀態、完成標記與續答；之後關閉重開，核對同一份紀錄。
