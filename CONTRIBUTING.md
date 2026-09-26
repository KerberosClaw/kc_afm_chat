# 貢獻方式

> English summary: Keep changes small, preserve the storage contract, and verify both
> the core tests and the native app. Real model tests are opt-in and use synthetic data.

本程式維持小型本機聊天工具的範圍。功能變更請說清楚使用情境；儲存格式變更需有
版本與恢復策略。不要把對話、真實照片、本機路徑、簽名資料或憑證提交進 repo。

提交前執行 `swift test` 與 `scripts/build.sh`。介面變更另需開 App 操作；模型
路徑變更需在相容 Mac 以合成資料執行 `swift run AFMChatProbe <new-directory>`。
回報時分開寫「假模型測試」「原生模型」「GUI 操作」，不要用其中一項代替全部。

README.md 為英文、README_zh.md 為正體中文；docs 技術文件以正體中文搭配短英文
摘要。新文件從 README 掛連結，改變資料契約時同步 DATA_FORMAT 與 USAGE。
