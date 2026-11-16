# POCKET

말하면 AI가 할 일과 일정으로 정리해 주는 개인용 iOS 앱입니다. 길게 받아 적는 메모, 사야 할 것을 모아 두는 Buy 목록, 집중 타이머, 홈 화면 위젯도 있습니다. 서버는 따로 없습니다. 데이터는 폰에만 저장되고 Claude는 앱에서 바로 부릅니다.

디자인: https://www.figma.com/design/sq5mf2NrgqFV8mr4AikrMY

## 탭

| 탭 | 하는 일 |
|---|---|
| Todo | 할 일 목록. 날짜가 없는 할 일도 여기에 모입니다 |
| Plan | 주간 날짜 줄과 하루 일정. 목록 보기와 시간표 보기를 오갑니다 |
| Chat | 말하거나 써서 AI에게 맡깁니다. 미리 본 뒤 저장하고 되돌릴 수 있습니다 |
| Memo | 길게 말한 내용을 받아 적습니다 |
| Buy | 살 것 목록. 산 것은 3일 뒤 자동으로 지워집니다 |

## 빌드

```sh
brew install xcodegen
xcodegen generate
open Pocket.xcodeproj
```

Xcode에서 서명할 Apple 계정을 고른 뒤 폰에 설치합니다. Claude API 키는 앱의 설정 화면에서 넣습니다. 키는 키체인에 저장되고 이 저장소에는 남지 않습니다.

## 시뮬레이터에서 AI 쓰기

Debug 빌드는 키체인에 키가 없으면 환경변수 `ANTHROPIC_API_KEY`를 읽습니다. 키 이름은 `.env.example`에 있습니다. 셸에 키를 불러온 뒤 실행합니다.

```sh
scripts/run-sim.sh "POCKET 13 mini" -tab chat
```

시뮬레이터에서는 한국어 음성 인식 모델을 불러오지 못해 음성 입력이 안 될 수 있습니다. 음성은 실제 폰에서 확인하세요.

## 테스트

```sh
xcodebuild -project Pocket.xcodeproj -scheme Pocket \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= test
```

Debug 빌드에 실행 인자 `-demo`를 주면 메모리에 넣은 예시 데이터로 뜹니다.
