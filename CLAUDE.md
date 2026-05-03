# CLAUDE.md — rb-translation-mac

## Position

Ruby native binding for Apple's Translation framework. Two-tier: lightweight `.bundle` (`LanguageAvailability`) and heavy helper subprocess (`TranslationSession` via SwiftUI hosting). Sibling to `rb-vision-ocrmac`, `rb-vision-mac`, `rb-natural-language-mac`, `rb-speech-mac`, `rb-sound-analysis-mac`. Built on `bash0C7/swift_gem`.

## Core design principles

1. **Two-tier by necessity, not by choice.** Apple's Translation framework forces the split: `LanguageAvailability` is plain Swift, but `TranslationSession` is delivered only through a SwiftUI `.translationTask` modifier. The `.bundle` handles the former, a helper subprocess handles the latter.
2. **Helper hosts SwiftUI in CLI.** `NSApplication.shared.setActivationPolicy(.accessory)` + `NSHostingView` in a borderless invisible window. `.translationTask` ticks inside the standard `NSApplication.run()` loop.
3. **Result types over plain returns** for the heavy tier. `TranslationResult` and `PrepareResult` (`Data.define`) carry `:success` and `:error`; `:error` is one of `ModelNotInstalledError`, `UnsupportedLanguagePairError`, `TimeoutError`, `HelperSpawnError`, `HelperCrashError`. Lightweight tier returns plain `Array<String>` or `Symbol`.
4. **30s helper timeout.** `DispatchQueue.main.asyncAfter` exits with code 4 if not finished.
5. **Translate is sheet-free.** Before invoking `session.translate`, the helper checks `LanguageAvailability.status` and short-circuits to exit 2 if not `.installed`. `prepare` is the explicit "show download sheet" path.
6. **Bundle-install pre-downloads the default pair.** `rake translation_mac:prepare_models` runs after `compile`. `CI_SKIP=1` opts out for CI.
7. **macOS 15.0+.** Diverges from sibling gems' `.macOS(.v12)` baseline because Translation requires it. Apple docs say 14.4+ but the compiler reports `TranslationSession` and `.translationTask` as `@available(macOS 15.0, *)` (verified 2026-05-02).
8. **Scaffold parity.** `swift_gem new rb-translation-mac` produces a skeleton whose only diffs are: implementation body, helper sources, Resources/Info.plist, helper Makefile rules, prepare_models Rake task, README, CLAUDE.md.

## Architecture

```
[caller (Ruby)]
  │
  ▼
lib/translation_mac.rb            ← module entry, helper_path getter/setter
  │
  ├─ require_relative "translation_mac/translation_mac"   (.bundle, lightweight)
  │   └─ TranslationMac.supported_languages, .status
  │
  ├─ require_relative "translation_mac/result"
  ├─ require_relative "translation_mac/errors"
  └─ require_relative "translation_mac/helper_client"
      └─ TranslationMac.translate, .prepare
          → Open3.capture3 → ext/.../TranslationMacHelper
                              └─ NSApplication.shared (.accessory)
                                 └─ NSHostingView(rootView: TranslateView)
                                    └─ .translationTask(config) { session in
                                          await session.translate(text)
                                       }
```

## Module boundaries

| Layer | Responsibility |
|---|---|
| `lib/translation_mac.rb` | Require children, declare `module TranslationMac`, `DEFAULT_HELPER_PATH`, `helper_path` accessors, public `translate` / `prepare` |
| `lib/translation_mac/errors.rb` | `Error` base + 5 subclasses |
| `lib/translation_mac/result.rb` | `TranslationResult` / `PrepareResult` Data classes |
| `lib/translation_mac/helper_client.rb` | `Open3.capture3` wrapper, exit code → error mapping |
| `ext/.../translation_mac.c` | `Init_translation_mac` exposes `supported_languages` (no args) and `status` (kw args from:/to:) |
| `ext/.../TranslationMac/TranslationMacBridge.swift` | `@c` (SE-0495) exports for the two methods + `_free` |
| `ext/.../TranslationMac/TranslationMac.swift` | `LanguageAvailability` async wrapper, blocks via `DispatchSemaphore` |
| `ext/.../TranslationMacHelper/main.swift` | argv parser, exit-code dispatch |
| `ext/.../TranslationMacHelper/HelperApp.swift` | `NSApplication.shared` + `NSHostingView` + 30s timeout |
| `ext/.../TranslationMacHelper/TranslateView.swift` | SwiftUI view with `.translationTask`. Imports `_Translation_SwiftUI` explicitly — Apple's SE-0367 cross-import overlay that is not pulled in automatically against the MacOSX26.2 SDK; it is public API and safe to ship |
| `ext/.../extconf.rb` | `SwiftGem::Mkmf.create_swift_makefile` for the .bundle, then appends helper build/codesign/install/post_install Make rules |
| `ext/.../Resources/Info.plist` | `CFBundleIdentifier` for stable codesign identity (no TCC strings — Translation framework is not TCC-gated) |
| `Rakefile` | `Rake::ExtensionTask` + `translation_mac:prepare_models` task |

Helper exit codes: `0` success, `2` model-not-installed, `3` unsupported language pair (also covers the unreachable-in-practice macOS-version-too-old guard), `4` helper timeout, `5` other helper crash. Exit 3 is intentionally overloaded because both conditions are terminal "this pair will never work" signals from the caller's perspective.

## Build flow

`bundle exec rake compile`:

1. `Rake::ExtensionTask` runs `extconf.rb` from `tmp/<arch>/translation_mac/<ruby-ver>/`
2. `swift_gem`'s `create_swift_makefile` generates the .bundle Make rules
3. `extconf.rb` appends helper rules: `helper`, `helper_install`, `post_install` (which runs `rake translation_mac:prepare_models`)
4. `make all` chains: `.bundle build` → `helper` (`swift build --product TranslationMacHelper` + `codesign`) → `helper_install` → `post_install`
5. Final state: `lib/translation_mac/translation_mac.bundle` + `lib/translation_mac/TranslationMacHelper`

`CI_SKIP=1 bundle exec rake compile` skips the post_install language model download.

## TDD discipline

- t-wada style: RED → GREEN → REFACTOR independent commits (per global CLAUDE.md)
- `test-unit`. `bundle exec rake test`
- Lightweight tier tests always run.
- `translate`/`prepare` integration tests gate on `ENV["CI_SKIP"]` AND `LanguageAvailability.status == :installed` for the test pair.
- HelperClient unit tests use `test/fixtures/fake_helper.sh` driven by env vars (`FAKE_EXIT`, `FAKE_STDOUT`, `FAKE_STDERR`, `FAKE_SIGNAL`) — same pattern as rb-speech-mac.
- Scaffold-regen check: when `swift_gem` changes, run `swift_gem new rb-translation-mac` into a tmpdir and diff for parity.

## Related projects

- `~/dev/src/github.com/bash0C7/swift_gem` — framework parent
- `~/dev/src/github.com/bash0C7/rb-speech-mac` — sibling helper-subprocess gem (TCC-gated; this gem inherited the helper structure but skipped TCC plumbing)

## Environment requirements

- macOS 15.0+ (`Package.swift` declares `.macOS(.v15)`)
- Apple Silicon (arm64-darwin) assumed
- Swift 6.3+
- Ruby 3.2+, bundler 4.x, rake-compiler 1.2+
- During development, `Gemfile` references swift_gem via `gem "swift_gem", path: "../swift_gem"`
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
