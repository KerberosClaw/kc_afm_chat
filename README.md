# A chat app that fits in a context window this small

[正體中文](README_zh.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![macOS 27+](https://img.shields.io/badge/macOS-27+-blue.svg)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange.svg)](https://swift.org)

Apple ships a language model inside macOS. It runs on your Mac, costs nothing, and on
the machine we tested it holds 4,096 tokens — enough for a real conversation, nowhere
near enough for an agent. We measured that before writing any interface, and AFM Chat
is what fits inside the answer: a small native window for the things this model is
actually good at, with automatic summarization so a long chat degrades into a summary
instead of an error.

The interface is currently in Traditional Chinese.

## Requirements

- Apple Silicon Mac running **macOS 27 or later**.
- **Xcode 27 or later**, selected with `xcode-select`.
- Apple Intelligence enabled and its on-device model ready.

That is a narrow slice of machines and we are not going to pretend otherwise. The app
reads the model's availability, name and context capacity at runtime instead of
hardcoding them, because those numbers move with hardware and OS version. No API key,
Python package or paid developer membership is required for the default local build.

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

## What it does

- Streaming text replies, with a Stop button that keeps whatever arrived before it.
- One image per message: paste, drop, or select a file.
- Automatic summarization near the context limit, with a progress state and a visible
  marker once it finishes. The original messages stay in the transcript.
- Local conversations with search, rename and delete.
- JSONL conversation records as the source of truth; the SQLite index is disposable
  and rebuildable.

## What it does not do

User messages are saved when sent. Assistant messages are saved on completion, normal
cancellation or a handled failure, so a crash can still lose an unfinished stream. We
would rather say that than claim durability we never tested. Compaction drops detail
by design; it is a summary, not unlimited model memory. On the OS we tested, the
framework's image token counting fails outright, so the app budgets images
conservatively rather than pretending to know the real cost.

The app uses `SystemLanguageModel.default`. No cloud fallback, no account, no
telemetry, no agent tools, no HTTP server. Data is ordinary local plaintext, not
encrypted by the app. See [security and privacy](SECURITY.md).

## Documentation

- [Usage](docs/USAGE.md)
- [Installation and signing](docs/INSTALL.md)
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

The probe requires a nonexistent output directory and an available Apple model. The
automated core tests run against a fake model, which means they prove the storage and
turn logic holds together. They certify nothing about model quality.

## License

[MIT](LICENSE). This license covers this repository's code, not Apple's models or
frameworks. AFM Chat is an independent project and is not affiliated with Apple.
