# CLAUDE.md — rb-translation-mac

## Position

Ruby binding for Apple's Translation framework. All 4 public APIs (`supported_languages`, `status`, `translate`, `prepare`) run inside a SwiftUI helper subprocess (`TranslationMacHelper`). Sibling to `rb-vision-ocrmac`, `rb-vision-mac`, `rb-natural-language-mac`, `rb-speech-mac`, `rb-sound-analysis-mac`.

## Core design principles

1. **Subprocess-only architecture.** All 4 APIs go through `TranslationMacHelper`. `LanguageAvailability` is SwiftUI-independent, but its async APIs require an active main run loop; `NSApplication.shared.run()` in the helper provides that. `TranslationSession` additionally requires a SwiftUI `.translationTask` modifier and cannot be instantiated directly.
2. **Helper hosts SwiftUI in CLI.** `NSApplication.shared.setActivationPolicy(.accessory)` + `NSHostingView` in a borderless invisible window. `.translationTask` ticks inside the standard `NSApplication.run()` loop.
3. **Result types over plain returns** for the heavy tier. `TranslationResult` and `PrepareResult` (`Data.define`) carry `:success` and `:error`; `:error` is one of `ModelNotInstalledError`, `UnsupportedLanguagePairError`, `TimeoutError`, `HelperSpawnError`, `HelperCrashError`. Lightweight tier returns plain `Array<String>` or `Symbol`.
4. **30s helper timeout.** `DispatchQueue.main.asyncAfter` exits with code 4 if not finished.
5. **Translate is sheet-free.** Before invoking `session.translate`, the helper checks `LanguageAvailability.status` and short-circuits to exit 2 if not `.installed`. `prepare` is the explicit "show download sheet" path.
6. **Bundle-install pre-downloads the default pair.** `rake translation_mac:prepare_models` runs after `compile`. `CI_SKIP=1` opts out for CI.
7. **macOS 15.0+.** Diverges from sibling gems' `.macOS(.v12)` baseline because Translation requires it. Apple docs say 14.4+ but the compiler reports `TranslationSession` and `.translationTask` as `@available(macOS 15.0, *)` (verified 2026-05-02).

## Architecture

```
[caller (Ruby)]
  │
  ▼
lib/translation_mac.rb            ← module entry, helper_path getter/setter
  │
  ├─ require_relative "translation_mac/result"
  ├─ require_relative "translation_mac/errors"
  └─ require_relative "translation_mac/helper_client"
      └─ TranslationMac.supported_languages, .status, .translate, .prepare
          → Open3.capture3 → lib/translation_mac/TranslationMacHelper
                              └─ NSApplication.shared (.accessory)
                                 └─ argv dispatch:
                                    ├─ "languages" → LanguageAvailability async
                                    ├─ "status"    → LanguageAvailability async
                                    ├─ "translate" → NSHostingView(TranslateView)
                                    │                └─ .translationTask { session in
                                    │                      await session.translate(text) }
                                    └─ "prepare"   → NSHostingView(TranslateView)
                                                     └─ .translationTask(prepare:)
```

## Module boundaries

| Layer | Responsibility |
|---|---|
| `lib/translation_mac.rb` | Require children, declare `module TranslationMac`, `DEFAULT_HELPER_PATH`, `helper_path` accessors, public `supported_languages` / `status` / `translate` / `prepare` |
| `lib/translation_mac/errors.rb` | `Error` base + 5 subclasses |
| `lib/translation_mac/result.rb` | `TranslationResult` / `PrepareResult` Data classes |
| `lib/translation_mac/helper_client.rb` | `Open3.capture3` wrapper, exit code → error mapping, all 4 API methods |
| `ext/.../TranslationMacHelper/main.swift` | argv parser, exit-code dispatch |
| `ext/.../TranslationMacHelper/HelperApp.swift` | `NSApplication.shared` + `NSHostingView` + 30s timeout |
| `ext/.../TranslationMacHelper/TranslateView.swift` | SwiftUI view with `.translationTask`. Imports `_Translation_SwiftUI` explicitly — Apple's SE-0367 cross-import overlay that is not pulled in automatically against the MacOSX26.2 SDK; it is public API and safe to ship |
| `ext/.../Resources/Info.plist` | `CFBundleIdentifier` for stable codesign identity (no TCC strings — Translation framework is not TCC-gated) |
| `Rakefile` | `:helper_build` task (`swift build -c release` → `codesign` → `FileUtils.install` to `lib/translation_mac/TranslationMacHelper`) + `translation_mac:prepare_models` task |

Helper exit codes: `0` success, `2` model-not-installed, `3` unsupported language pair (also covers the unreachable-in-practice macOS-version-too-old guard), `4` helper timeout, `5` other helper crash. Exit 3 is intentionally overloaded because both conditions are terminal "this pair will never work" signals from the caller's perspective.

## Build flow

`bundle exec rake helper_build`:

1. `swift build -c release --product TranslationMacHelper`
2. `codesign --force --sign -` on the built binary
3. `FileUtils.install` to `lib/translation_mac/TranslationMacHelper`
4. Final state: `lib/translation_mac/TranslationMacHelper` (executable)

`CI_SKIP=1 bundle exec rake helper_build` skips the post-install language model download.

## TDD discipline

- t-wada style: RED → GREEN → REFACTOR independent commits (per global CLAUDE.md)
- `test-unit`. `bundle exec rake test`
- Lightweight tier tests always run.
- `translate`/`prepare` integration tests gate on `ENV["CI_SKIP"]` AND `LanguageAvailability.status == :installed` for the test pair.
- HelperClient unit tests use `test/fixtures/fake_helper.sh` driven by env vars (`FAKE_EXIT`, `FAKE_STDOUT`, `FAKE_STDERR`, `FAKE_SIGNAL`) — same pattern as rb-speech-mac.

## Related projects

- `~/dev/src/github.com/bash0C7/rb-speech-mac` — sibling helper-subprocess gem (TCC-gated; this gem inherited the helper structure but skipped TCC plumbing)

## Environment requirements

- macOS 15.0+ (`Package.swift` declares `.macOS(.v15)`)
- Apple Silicon (arm64-darwin) assumed
- Swift 6.3+
- Ruby 3.2+, bundler 4.x
- `Gemfile.lock` is library-style: not git-tracked

## Prohibitions

- No Python source (per global CLAUDE.md)
- Do not git-track `Gemfile.lock`
- Do not promise determinism of translation results — Apple updates models
- Do not log or persist translated text
- Do not bypass `CI_SKIP` in CI environments — bundle install with prepare_models can hang on the macOS download dialog
- Do not raise on translation failure; return Result with `:error` populated
- Commit messages in English, conventional commits style
- `.claude/` is committed
