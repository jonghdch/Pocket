#!/bin/sh
# 셸의 ANTHROPIC_API_KEY 를 넘겨 시뮬레이터에서 POCKET 을 띄운다 (Debug 빌드 전용).
# 키는 이 스크립트가 직접 읽지 않는다. 실행 전에 셸에 불러 둔다. README 의 "시뮬레이터에서 AI 쓰기" 참고.
# 사용: scripts/run-sim.sh [시뮬레이터 이름] [앱 인자...]   예) scripts/run-sim.sh "POCKET 13 mini" -tab chat
set -eu
cd "$(dirname "$0")/.."
DEVICE="${1:-POCKET 13 mini}"
[ $# -gt 0 ] && shift

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "ANTHROPIC_API_KEY 가 셸에 없어요. README 의 \"시뮬레이터에서 AI 쓰기\"를 보고 불러와 주세요." >&2
  exit 1
fi

xcodegen generate >/dev/null
xcodebuild -project Pocket.xcodeproj -scheme Pocket -configuration Debug \
  -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build >/dev/null

UDID=$(xcrun simctl list devices available | grep -F "$DEVICE (" | head -n 1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator
xcrun simctl install "$UDID" build/Build/Products/Debug-iphonesimulator/POCKET.app
SIMCTL_CHILD_ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" xcrun simctl launch --terminate-running-process "$UDID" com.jonghdch.pocket "$@"
echo "POCKET 을 $DEVICE 에서 띄웠어요."
