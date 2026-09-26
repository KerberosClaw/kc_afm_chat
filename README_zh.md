# AFM Chat

[English](README.md)

一個使用 Apple 裝置端 Foundation Models 的 macOS 小程式。可以傳文字或單張圖片、
保留本機對話，並在接近上下文上限時自動整理舊內容。介面目前使用正體中文。

## 需求

- Apple Silicon Mac、**macOS 27 以上**。
- **Xcode 27 以上**，並以 `xcode-select` 選取。
- 已開啟 Apple Intelligence，裝置端模型已準備完成。

模型名稱、可用性與上下文大小由框架即時回報；不同機器及系統版本可能不同。
預設的本機建置不需要 API key、Python 套件或付費開發者會員。

## 建置與執行

```sh
git clone https://github.com/KerberosClaw/kc_afm_chat.git
cd kc_afm_chat
scripts/build.sh
open '.build/xcode/Build/Products/Release/AFM Chat.app'
```

腳本使用本機 ad-hoc 簽名；若要用自己的身分簽名，可設定 `AFM_CHAT_SIGN_IDENTITY`。
也可開啟 `kc_afm_chat.xcodeproj`，自行選擇 Team 與 Bundle Identifier，執行
**AFMChat** scheme。詳見[安裝與簽名](docs/INSTALL.md)。

## 功能

- 串流回答與停止按鈕。
- 每則訊息一張圖，可貼上、拖入或選取。
- 自動整理舊對話，顯示整理中狀態與完成標記，原始訊息仍可閱讀。
- 本機對話清單、搜尋、重新命名與刪除。
- JSONL 為原始紀錄，SQLite 為可重建的搜尋索引。

使用者訊息送出時保存；模型回答在完成、正常停止或可處理錯誤時保存。
程序閃退可能丟失尚未完成的串流內容。摘要可能遺漏細節，不代表模型有無限記憶。
實測系統的圖片 token 計數 API 會失敗，因此圖片採保守預算，並在介面標成估算。

App 使用 `SystemLanguageModel.default`，沒有雲端 fallback、帳號、遙測、代理工具
或 HTTP server。資料是本機明文，App 未另行加密，詳見[安全與隱私](SECURITY.md)。

## 文件與開發

- [使用手冊](docs/USAGE.md)
- [設計範圍](docs/DESIGN.md)、[架構](docs/ARCHITECTURE.md)
- [資料格式與恢復](docs/DATA_FORMAT.md)
- [驗證與限制](docs/VERIFICATION.md)、[貢獻方式](CONTRIBUTING.md)

```sh
swift test
scripts/build.sh
# 選用：使用原生模型，建立合成測試對話；目錄必須尚不存在。
swift run AFMChatProbe /tmp/afm-chat-probe-new-directory
```

核心測試使用假模型；真實模型品質需另外驗證。

## 授權

[MIT](LICENSE)。此授權涵蓋本 repo 程式碼，不涵蓋 Apple 的模型或框架。
這是獨立專案，與 Apple 無從屬關係。
