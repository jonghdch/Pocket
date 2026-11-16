# POCKET

Personal iOS app: speak, and AI turns it into todos and events. Includes a memo tab for long dictation, focus timers, and home screen widgets. There is no server: data stays on the phone and Claude is called directly from the app.

Design: https://www.figma.com/design/sq5mf2NrgqFV8mr4AikrMY

## Build

```sh
brew install xcodegen
xcodegen generate
open Pocket.xcodeproj
```

Run on a phone from Xcode with your Apple account selected for signing. Enter the Claude API key in the app under Settings; it is kept in the Keychain and never stored in this repository.

## Test

```sh
xcodebuild -project Pocket.xcodeproj -scheme Pocket \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= test
```

The `-demo` launch argument (debug builds) runs on seeded in-memory data.
