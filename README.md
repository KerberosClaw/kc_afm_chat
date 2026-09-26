# AFM Chat

[正體中文](README_zh.md)

A small native macOS chat app for Apple's on-device Foundation Models. Chat with text
or one image at a time, keep conversations locally, and continue longer chats with
automatic context compaction. The interface currently uses Traditional Chinese.

## Requirements

- Apple Silicon Mac running **macOS 27 or later**.
- **Xcode 27 or later**, selected with `xcode-select`.
- Apple Intelligence enabled and its on-device model ready.

The app reads the model's availability, name and context capacity at runtime. Model
capabilities vary with hardware and OS versions. No API key, Python package or paid
developer membership is required for the default local build.

## Build and run

```sh
git clone https://github.com/KerberosClaw/kc_afm_chat.git
cd kc_afm_chat
scripts/build.sh
open '.build/xcode/Build/Products/Release/AFM Chat.app'
```

The script builds locally and applies an ad-hoc signature. To use your own signing
identity, set `AFM_CHAT_SIGN_IDENTITY` before building. You can also open
`kc_afm_chat.xcodeproj`, select your own team and bundle identifier, then run the
**AFMChat** scheme. See [installation and signing](docs/INSTALL.md).

## Features

- Streaming text replies with a Stop button.
- One image per message: paste, drop, or select a file.
- Automatic summarization near the context limit, with progress and a visible
  completion marker; original messages remain in the history.
- Local conversations with search, rename and delete.
- JSONL conversation records as the source of truth; a rebuildable SQLite index.

User messages are saved when sent. Assistant messages are saved on completion,
normal cancellation or a handled failure. A crash can lose the unfinished stream.
Compaction can omit details; it is not unlimited model memory. On the tested OS,
image token counting fails in the framework, so the app budgets images conservatively.

The app uses `SystemLanguageModel.default`. It has no cloud fallback, account,
telemetry, agent tools or HTTP server. Data is ordinary local plaintext, not encrypted
by the app. See [security and privacy](SECURITY.md).

## Documentation

- [Usage](docs/USAGE.md)
- [Design and scope](docs/DESIGN.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Storage contract and recovery](docs/DATA_FORMAT.md)
- [Verification and known limits](docs/VERIFICATION.md)
- [Contributing](CONTRIBUTING.md)

## Development

```sh
swift test
scripts/build.sh
# Optional: runs real local inference and creates synthetic conversations.
swift run AFMChatProbe /tmp/afm-chat-probe-new-directory
```

The probe requires a nonexistent output directory and an available Apple model.
Automated core tests use a fake model; they do not certify model quality.

## License

[MIT](LICENSE). This license covers this repository's code, not Apple's models or
frameworks. AFM Chat is an independent project and is not affiliated with Apple.
