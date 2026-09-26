#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
xcodebuild -project kc_afm_chat.xcodeproj -scheme AFMChat -configuration Release \
  -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build
app_path="$repo_root/.build/xcode/Build/Products/Release/AFM Chat.app"
codesign --force --sign "${AFM_CHAT_SIGN_IDENTITY:--}" "$app_path"
codesign --verify --strict "$app_path"
printf '\nBuilt: %s\n' "$app_path"
