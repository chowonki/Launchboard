#!/bin/bash
# Xcode를 열지 않고 터미널에서 Release 빌드 후 /Applications에 설치합니다.
set -euo pipefail
cd "$(dirname "$0")"
xcodebuild -project Launchboard.xcodeproj -scheme Launchboard -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY=- build 2>&1 | tee build-log.txt | grep -E "error:|warning: .*Launchboard|BUILD" || true
APP="build/Build/Products/Release/Launchboard.app"
if [ ! -d "$APP" ]; then
  echo "❌ 빌드 실패. build-log.txt에서 'error:' 줄을 Claude에게 붙여 주세요."
  exit 1
fi
rm -rf /Applications/Launchboard.app
cp -R "$APP" /Applications/
echo "✅ /Applications/Launchboard.app 설치 완료"
open /Applications/Launchboard.app
