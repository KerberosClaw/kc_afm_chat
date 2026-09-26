# 安裝與簽名

> English summary: Build with Xcode 27 on an Apple Intelligence capable Mac running
> macOS 27. The shell build uses a local ad-hoc signature; each user can choose their
> own signing identity. No shared development team or certificate is included.

## 系統準備

在系統設定開啟 Apple Intelligence，等待模型下載完成。App 啟動時顯示框架回報的
可用狀態，模型尚未就緒時無法送出。模型準備可能需要網路；聊天使用裝置端模型。

```sh
xcodebuild -version
xcode-select -p
```

需要完整 Xcode 27 SDK，只有 Command Line Tools 不夠。若版本指錯，請在 Xcode
設定的 Locations 選擇對應的 Command Line Tools。第一版使用 macOS 27 的圖片與
token 計數 API，不提供舊版系統的相容模式。

## 腳本建置

在 repo 根目錄執行：

```sh
scripts/build.sh
open '.build/xcode/Build/Products/Release/AFM Chat.app'
```

產物在 `.build/xcode/Build/Products/Release/AFM Chat.app`。腳本先關閉 Xcode 自動
簽名，再以 `codesign --sign -` 做 ad-hoc 簽名，並執行 `codesign --verify --strict`。
這是自己建置、自己執行的流程，沒有公證過的下載檔。

若已持有自己的簽名身分：

```sh
AFM_CHAT_SIGN_IDENTITY='your signing identity' scripts/build.sh
```

不要把憑證、私鑰、Team ID 或本機簽名設定提交進 repo。

## Xcode 建置

1. 開啟 `kc_afm_chat.xcodeproj`，選 **AFMChat** scheme。
2. 選 My Mac 為目的地。
3. Signing & Capabilities 選自己的 Team；需要時更換 Bundle Identifier。
4. Run。若只需本機 ad-hoc 版本，可直接使用上述腳本。

本 repo 不要求 XcodeGen、Homebrew 或第三方 Swift 套件。SQLite 使用系統函式庫。

## 資料與移除

預設資料位置為 `~/Library/Application Support/AFMChat/`，選單可開啟。
關閉 App 後可複製整個資料夾備份或搬到另一部相容 Mac；先保留原本備份，不合併兩份
正在使用的資料。刪除 App 不會刪除對話；要完整移除，關閉 App 後另行刪除資料夾。

開發驗證可指定另一個資料夾：

```sh
AFM_CHAT_DATA_DIR=/tmp/afm-chat-manual-check \
  '.build/xcode/Build/Products/Release/AFM Chat.app/Contents/MacOS/AFM Chat'
```

同一資料目錄只允許一個程序寫入；第二個程序會顯示錯誤。
