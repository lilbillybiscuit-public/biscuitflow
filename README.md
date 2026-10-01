# BiscuitFlow

A native macOS push-to-talk dictation app that runs fully on-device.
Hold **⌥D** (or any shortcut you record), talk, let go: your words are transcribed locally by
**Qwen3-ASR 0.6B** and pasted into whatever app has focus.

## Features

- **Push-to-talk** — hold the dictation shortcut (default **⌥D**); release to transcribe & paste.
  Record any combo (⌃⇧Space, F5, …) or a lone modifier (fn, right ⌥) in Settings; combos are swallowed so ⌥D doesn't type "∂".
- **Hands-free** — double-tap the key, or press key + Space; press again to finish. Esc cancels.
- **Dictation pill** — a frosted chip at the bottom of the screen: a resting crumb → "Hold ⌥D" on hover →
  record dot + scrolling level history + timer while listening → lock / Done in hands-free → "Transcribing".
  Never steals focus.
- **On-device ASR** — Qwen3-ASR 0.6B (MLX, 5-bit) via [soniqo/speech-swift](https://github.com/soniqo/speech-swift),
  **bundled inside the app** (`Contents/Resources/Models`, ~1 GB) — no download, works offline. 30+ languages, auto-detect.
- **Cleanup** — filler-word removal, smart spacing/capitalization based on the text around the caret (Accessibility).
- **Dictionary** — custom words bias the model (passed as Qwen3-ASR context) and optional "sounds like → spelling" replacements.
- **Snippets** — say a cue phrase, get a block of text.
- **Hub** — history with search/copy, words dictated, WPM, day streak; settings; onboarding.
- Clipboard is restored after pasting; ⌘V is resolved through the current keyboard layout.
- Optional: mute system audio while dictating, launch at login, mic picker, menu-bar item.

## Performance (M-series host, 10.5 s English clip)

| Where | Transcribe time |
|---|---|
| M5 Max host | **0.09 s** (~115× realtime), model load 0.5 s |
| Parallels macOS 15.3 VM (paravirtual GPU) | 0.18–0.45 s |

Core ML was evaluated and dropped for now: the published Qwen3-ASR Core ML decoder is exported with a
fixed 128-token batch, so every generated token pays for 128 positions (~33 ms/token on the ANE vs ~2 ms on MLX).
A T=1 decode export would fix that.

For continuity with existing installs, the bundle identifier remains `dev.billyqian.hflow` and
local data stays in `~/Library/Application Support/HFlow`. Debug environment variables retain the `HFLOW_` prefix.

## Build

Requires macOS 15+, Apple Silicon, Xcode 27 (release toolchain; the beta's stdlib breaks swift-collections),
and `brew install xcodegen`. First build: `xcodebuild -downloadComponent MetalToolchain` (MLX shaders).
No signing certificate or Apple account is needed.

```sh
scripts/build.sh            # fetches the model into Models/ (once), → build/BiscuitFlow.app (Release)
open build/BiscuitFlow.app
```

### Signing

Builds are **ad-hoc signed** by default — no certificate needed. Trade-offs:

- macOS ties the Accessibility grant to the exact signature, so after every rebuild you must toggle
  BiscuitFlow off/on in System Settings → Privacy & Security → Accessibility (or `tccutil reset Accessibility dev.billyqian.hflow`).
- On other Macs, Gatekeeper blocks a downloaded ad-hoc app: right-click → Open (or System Settings → Open Anyway),
  or `xattr -dr com.apple.quarantine BiscuitFlow.app`.

To keep the Accessibility grant across rebuilds without an Apple account, create a self-signed
code-signing certificate (Keychain Access → Certificate Assistant → Create a Certificate…, type *Code Signing*),
then build with it. With an Apple Developer account, use your team (Developer ID + notarization for distribution):

```sh
SIGN_IDENTITY="BiscuitFlow Local" scripts/build.sh   # self-signed identity from your keychain
TEAM_ID=ABCDE12345 scripts/build.sh                  # "Apple Development" for that team
```

### Model

`scripts/fetch_model.sh` copies `aufklarer/Qwen3-ASR-0.6B-MLX-5bit` from the speech-swift cache or downloads it
from Hugging Face into `Models/` (git-ignored); a build phase rsyncs it into the app bundle before signing.

Grant **Microphone** and **Accessibility** when prompted. If you set the shortcut to fn and it opens the emoji picker,
set System Settings → Keyboard → "Press 🌐 key to" → *Do Nothing*.

## Testing

```sh
# Unit tests (text processing, stats, speech gate)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project BiscuitFlow.xcodeproj -scheme BiscuitFlow \
  -destination 'platform=macOS,arch=arm64' -clonedSourcePackagesDirPath .build/spm -derivedDataPath .build/DerivedData \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES

# Headless ASR benchmark (works over SSH / in a VM without a GUI session)
build/BiscuitFlow.app/Contents/MacOS/BiscuitFlow --bench tests/audio/sample1.wav --runs 3 [--language English]

# Replace the microphone with a file to exercise the whole hotkey → paste path
open -a build/BiscuitFlow.app --env HFLOW_TEST_AUDIO=$PWD/tests/audio/sample1.wav
```

Debug env vars: `HFLOW_TEST_AUDIO=<wav>` (fake mic), `HFLOW_DEBUG=1` (log modifier keys),
`HFLOW_HOTKEY_KEYCODE=58` (listen to a different physical key with the same modifier flag — Parallels
can only send left ⌥). Launch via `open` (LaunchServices), not `prlctl exec`, or TCC attributes permissions to `prltoolsd`.

Verified end-to-end in the Parallels macOS 15.3 VM: hold-to-talk (listening pill → paste into TextEdit → history),
double-tap hands-free (✕ / ■ pill → tap to stop → paste), smart spacing between consecutive dictations.

## Layout

```
BiscuitFlow/App      app entry, AppDelegate, menu bar + hub scenes
BiscuitFlow/Core     HotkeyMonitor (CGEventTap), AudioRecorder (AVAudioEngine→16 kHz), Transcriber (bundled Qwen3-ASR),
               TextProcessor, TextInserter (pasteboard + ⌘V, AX caret context), DictationController (state machine),
               Store (JSON history/dictionary/snippets), Permissions, SoundPlayer, Benchmark
BiscuitFlow/UI       dictation pill overlay panel, hub (Home/Dictionary/Snippets/Settings/Onboarding), theme
reference/     optional local reference material (git-ignored, not shipped)
```
