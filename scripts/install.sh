#!/bin/zsh
# 배포용(Release)으로 빌드해서 ~/Applications/KotePomodoro.app에 설치하고 실행한다.
# 사용 전: Local.xcconfig.example을 Local.xcconfig로 복사하고 본인 Team ID를 넣어 두세요.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

if [[ ! -f Local.xcconfig ]]; then
  echo "Local.xcconfig가 없습니다. Local.xcconfig.example을 복사해서 Team ID를 넣어 주세요." >&2
  exit 1
fi

BUILD_DIR="$(mktemp -d)/build"
APP_NAME="KotePomodoro.app"
DEST="$HOME/Applications/$APP_NAME"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# 샌드박스는 유지하고 디버거 연결 권한(get-task-allow)은 빼고 서명한다
xcodebuild -scheme KotePomodoro -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" -xcconfig Local.xcconfig -allowProvisioningUpdates \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO CODE_SIGN_ENTITLEMENTS=Release.entitlements \
  build -quiet

# mac 알림은 앱이 임시 폴더가 아닌 ~/Applications에 있어야 동작한다
osascript -e 'quit app "KotePomodoro"' 2>/dev/null || true
sleep 1
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$BUILD_DIR/Build/Products/Release/$APP_NAME" "$DEST"
"$LSREGISTER" -f "$DEST"
rm -rf "${BUILD_DIR:h}"

open "$DEST"
echo "설치 완료: $DEST"
