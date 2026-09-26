# 上下文就這麼大，那就照這個大小做

[English](README.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![macOS 27+](https://img.shields.io/badge/macOS-27+-blue.svg)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)

Apple 把一顆語言模型放進 macOS 裡。它跑在你自己的 Mac 上，不用錢，而在我們實測的
那台機器上，它的上下文是 4,096 個 token：拿來好好聊天夠用，拿來跑 agent 差得遠。
我們是先把它量完才動手寫介面的，AFM Chat 就是照那個答案的尺寸做出來的。一個原生
小視窗，只做這顆模型真的做得好的事，並在額度快用完時自動整理舊對話，讓長對話的
下場是一份摘要，不是一個錯誤訊息。

介面目前使用正體中文。

## 需求

- Apple Silicon Mac，**macOS 27 以上**。
- **Xcode 27 以上**，並以 `xcode-select` 選取。
- 已開啟 Apple Intelligence，裝置端模型已準備完成。

三項都符合的機器不多，這點不粉飾。模型名稱、可用性與上下文大小都是執行時跟框架
要的，沒有寫死，因為那些數字會隨硬體與系統版本變動。預設的本機建置不需要 API
key、Python 套件或付費開發者會員。

## 建置與執行

```sh
git clone https://github.com/KerberosClaw/kc_afm_chat.git
cd kc_afm_chat
scripts/build.sh
open '.build/xcode/Build/Products/Release/AFM Chat.app'
```

腳本在本機建置並套用 ad-hoc 簽名。要用自己的簽名身分，建置前設定
`AFM_CHAT_SIGN_IDENTITY`。也可以開啟 `kc_afm_chat.xcodeproj`，自行選擇 Team 與
Bundle Identifier，執行 **AFMChat** scheme。詳見[安裝與簽名](docs/INSTALL.md)。

## 它會做什麼

- 串流回答，按停止會保留已經吐出來的那一段。
- 每則訊息一張圖，可貼上、拖入或選取。
- 接近上下文上限時自動整理舊對話，過程中顯示狀態，結束後留下完成標記。原始訊息
  仍留在紀錄裡。
- 本機對話清單、搜尋、重新命名與刪除。
- JSONL 是權威紀錄，SQLite 索引隨時可以砍掉重建。

## 它不會做什麼

使用者訊息在送出時保存，模型回答在完成、正常停止或可處理的錯誤時保存，所以程序
閃退仍可能丟掉尚未寫完的那段串流。與其宣稱沒驗過的耐久性，不如把這句寫出來。
整理本來就會丟掉細節，它是摘要，不是無限記憶。在實測的系統版本上，框架的圖片
token 計數直接失敗，所以 App 改用保守預算，不假裝自己知道真實成本。

App 使用 `SystemLanguageModel.default`。沒有雲端 fallback，沒有帳號，沒有遙測，
沒有代理工具，也沒有 HTTP server。資料是本機明文，App 未另行加密，詳見
[安全與隱私](SECURITY.md)。

## 文件

- [使用手冊](docs/USAGE.md)
- [安裝與簽名](docs/INSTALL.md)
- [設計範圍](docs/DESIGN.md)
- [架構](docs/ARCHITECTURE.md)
- [資料格式與恢復](docs/DATA_FORMAT.md)
- [驗證與限制](docs/VERIFICATION.md)
- [貢獻方式](CONTRIBUTING.md)

## 開發

```sh
swift test
scripts/build.sh
# 選用：使用原生模型，建立合成測試對話；目錄必須尚不存在。
swift run AFMChatProbe /tmp/afm-chat-probe-new-directory
```

探針需要一個尚不存在的輸出目錄，以及一顆可用的 Apple 模型。核心測試跑的是假
模型，它證明的是儲存與回合邏輯站得住，不證明模型品質。

## 授權

[MIT](LICENSE)。此授權涵蓋本 repo 程式碼，不涵蓋 Apple 的模型或框架。這是獨立
專案，與 Apple 無從屬關係。
