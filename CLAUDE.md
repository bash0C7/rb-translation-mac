# CLAUDE.md — rb-translation-mac

## Position

Ruby binding for Apple's Translation framework on macOS. The four public APIs (`supported_languages`, `status`, `translate`, `prepare`) run inside the `TranslationMacHelper` subprocess, a Swift Package Manager executable. Scaffolded from `bash0C7/swift_gem`. Sibling of `rb-vision-mac` and `rb-natural-language-mac`.

## Core design principles

1. Helper subprocess, no C extension. `LanguageAvailability`'s async APIs need an active main run loop, which a Ruby process does not run; the helper runs `NSApplication.shared.run()` as an `.accessory` app. Ruby talks to it with `Open3.capture3`, so the gem itself is pure Ruby.
2. `translate` uses `TranslationSession(installedSource:target:)`, which never downloads. The helper checks `LanguageAvailability.status` first and exits with 2 (not installed) or 3 (unsupported) before creating the session.
3. `prepare` is the only download path. `prepareTranslation()` needs a session from SwiftUI's `.translationTask`, so the helper hosts `PrepareView` in an `NSHostingView` inside a borderless 1x1 window.
4. Result types for the heavy tier. `TranslationResult` and `PrepareResult` (`Data.define`) carry `success` and `error`; `translate` and `prepare` never raise. The lightweight tier returns `Array<String>` or `Symbol` and degrades to `[]` / `:unsupported` when the helper fails.
5. 30-second helper timeout. `DispatchQueue.main.asyncAfter` exits with 4; it applies to every subcommand, including `prepare` while the system download prompt is open.
6. Scaffold parity where it applies. `xcrun swift`, `swift-tools-version: 6.4`, `.macOS(.v27)`, `task :swift`, `task compile: :swift`, `task :rbs`, `task test: %i[rbs compile]`, `sig/`, and the tracked `.bundle/config` follow swift_gem. The scaffold's C extension pieces (`extconf.rb`, `swift_mkmf.rb`, `<m>.c`, `@c` bridge, `Rake::ExtensionTask`, `rake-compiler`, `spec.extensions`) do not apply because nothing runs in the Ruby process.

## Architecture

```
[caller (Ruby)]
  │
  ▼
lib/translation_mac.rb                  ← module entry, helper_path accessors, public API
  │
  ▼
lib/translation_mac/helper_client.rb    ← Open3.capture3, exit code → Result / Symbol / Array
  │
  ▼
lib/translation_mac/TranslationMacHelper
  └─ NSApplication.shared (.accessory) + 30 s timeout
     ├─ languages → LanguageAvailability.supportedLanguages
     ├─ status    → LanguageAvailability.status(from:to:)
     ├─ translate → status check → TranslationSession(installedSource:target:).translate
     └─ prepare   → status check → NSHostingView(PrepareView)
                                    └─ .translationTask(source:target:) { prepareTranslation() }
```

Helper exit codes: `0` success, `2` model not installed, `3` unsupported language pair, `4` timeout, `5` any other failure (including usage errors). Standard output carries the result without a trailing newline; standard error carries the failure message.

## Module boundaries

| Layer | Responsibility |
|---|---|
| `lib/translation_mac.rb` | Requires the children, `DEFAULT_HELPER_PATH`, `helper_path` accessors, public `supported_languages` / `status` / `translate` / `prepare` |
| `lib/translation_mac/errors.rb` | `Error` and its five subclasses |
| `lib/translation_mac/result.rb` | `TranslationResult` / `PrepareResult` |
| `lib/translation_mac/helper_client.rb` | Runs the helper, maps exit codes to errors and output to values |
| `sig/translation_mac.rbs` | RBS and API documentation for everything above |
| `ext/translation_mac/Sources/TranslationMacHelper/main.swift` | Parses arguments into `Operation` and starts `HelperApp` |
| `ext/translation_mac/Sources/TranslationMacHelper/HelperApp.swift` | `Operation`, `ExitCode`, `finish`, and `HelperApp` (application loop, timeout, `LanguageAvailability`, `TranslationSession`) |
| `ext/translation_mac/Sources/TranslationMacHelper/PrepareView.swift` | SwiftUI view whose `.translationTask` calls `prepareTranslation()` |
| `ext/translation_mac/Resources/Info.plist` | Embedded into the helper's `__TEXT,__info_plist` by the linker for its bundle identifier and name |
| `Rakefile` | `task :swift` (build, ad hoc `codesign`, install), `task compile: :swift`, `task :rbs`, `task test: %i[rbs compile]`, `task console: :compile`, `translation_mac:prepare_models` |
| `locale/` | `translation_mac-locale` sub-gem with its own Gemfile, Rakefile, `sig/`, and tests |

## Build flow

`bundle exec rake compile`:

1. `xcrun swift build -c release --package-path ext/translation_mac --product TranslationMacHelper` (output in `ext/translation_mac/.build/release`)
2. `codesign -s - --force --identifier com.bash0c7.rb-translation-mac.helper --options runtime`
3. `FileUtils.install` to `lib/translation_mac/TranslationMacHelper`

`bundle exec rake test` validates the RBS, compiles, and runs the tests.

## TDD discipline

- t-wada style RED → GREEN → REFACTOR independent commits. test-unit. `bundle exec rake test`
- `HelperClient` unit tests use `test/fixtures/fake_helper.sh`, driven by `FAKE_EXIT`, `FAKE_STDOUT`, `FAKE_STDERR`, and `FAKE_SIGNAL`
- The remaining tests call the real helper. `CI_SKIP=1` omits the direct helper subprocess tests and the `translate` / `prepare` tests; the `translate` test and the installed-pair `prepare` test also omit themselves when `en-US` to `ja-JP` is not installed
- `locale/` tests run separately: `cd locale && bundle exec rake test`

## Related projects

- `~/dev/src/github.com/bash0C7/swift_gem` — scaffold origin
- `~/dev/src/github.com/bash0C7/rb-natural-language-mac` — its `examples/sentiment_score.rb` uses this gem
- `~/dev/src/github.com/bash0C7/rb-vision-mac` — sibling on the same scaffold

## Environment requirements

macOS 27+, Apple Silicon, Xcode 27 (Swift 6.4, builds run `xcrun swift`), Ruby 4.0+, bundler 4.x, rbs 4.x. `Gemfile.lock` is not git-tracked.

## Prohibitions

- No Python source
- No code comments. Swift is documented with DocC (`///`, `- Parameter`, `- Returns`, ``` ``symbol`` ``` links); Ruby is documented with `#` comments above declarations in `sig/translation_mac.rbs` and `locale/sig/translation_mac_locale.rbs`. History goes in commit messages
- Do not git-track `Gemfile.lock`
- Do not promise deterministic translations; Apple updates the models
- Do not log or persist translated text
- Do not download models from `translate`; downloads go through `prepare`
- Do not raise from `translate` or `prepare`; return a Result with `error` set
- Commit messages in English, conventional commits style
- `.claude/` is committed
