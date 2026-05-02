# rb-translation-mac — Design Spec

Date: 2026-05-02
Status: Approved (2026-05-02). Implementation tracked via writing-plans output.

## Position

Ruby native binding for Apple's Translation framework (`TranslationSession`, `LanguageAvailability`). Sibling to `rb-vision-ocrmac`, `rb-vision-mac`, `rb-natural-language-mac`, `rb-speech-mac`, `rb-sound-analysis-mac`. Built on `bash0C7/swift_gem`.

Unique aspects:
- Translation framework is **SwiftUI-only** for the actual `translate` API. Headless Swift CLI cannot directly invoke `TranslationSession.translate`.
- `LanguageAvailability` is the only SwiftUI-independent piece.
- This gem therefore adopts a **two-tier architecture**: lightweight ext (.bundle) for `LanguageAvailability` and heavy helper subprocess (with embedded SwiftUI hosting) for `translate` / `prepare`.

## Background research (2026-05-02)

- `TranslationSession` cannot be instantiated directly. It is delivered only through the `.translationTask(_:action:)` SwiftUI view modifier.
- `LanguageAvailability` is a plain class: `await languageAvailability.supportedLanguages`, `await languageAvailability.status(from:to:)`. Returns `.installed | .supported | .unsupported`.
- First-time translation triggers a system sheet asking the user to download the language model.
- Translation framework requires **macOS 14.4+** (other 5 sibling gems target `.macOS(.v12)`).
- Translation framework is **not TCC-gated** (no `NSTranslationUsageDescription` plist key needed).

Sources:
- [TranslationSession | Apple Developer Documentation](https://developer.apple.com/documentation/translation/translationsession)
- [Free, on-device translations with the Swift Translation API — polpiella.dev](https://www.polpiella.dev/swift-translation-api/)
- [Using the Translation framework — createwithswift.com](https://www.createwithswift.com/using-the-translation-framework-for-language-to-language-translation/)
- [Meet the Translation API — WWDC24](https://developer.apple.com/videos/play/wwdc2024/10117/)

## Public Ruby API

### Lightweight tier (.bundle direct, ~ms latency)

```ruby
TranslationMac.supported_languages
# => ["en-US", "ja-JP", "zh-Hans-CN", ...]   # Array<String> in BCP47

TranslationMac.status(from: "en-US", to: "ja-JP")
# => :installed | :supported | :unsupported
```

### Heavy tier (helper subprocess, ~hundreds of ms to seconds)

```ruby
TranslationMac.translate("Hello world", from: "en-US", to: "ja-JP")
# => TranslationMac::TranslationResult.new(text: "こんにちは世界", success: true, error: nil)
# => TranslationMac::TranslationResult.new(text: nil, success: false, error: <ModelNotInstalledError>)

TranslationMac.prepare(from: "en-US", to: "ja-JP")
# => TranslationMac::PrepareResult.new(status: :installed, success: true, error: nil)
# => TranslationMac::PrepareResult.new(status: :unknown, success: false, error: <UnsupportedLanguagePairError>)
```

### Result types (chosen H2 over H1 per user decision 2026-05-02)

```ruby
module TranslationMac
  TranslationResult = Data.define(:text, :success, :error)
  PrepareResult     = Data.define(:status, :success, :error)
end
```

### Error classes

```ruby
module TranslationMac
  class Error < StandardError; end
  class ModelNotInstalledError       < Error; end   # exit 2
  class UnsupportedLanguagePairError < Error; end   # exit 3
  class TimeoutError                 < Error; end   # exit 4
  class HelperSpawnError             < Error; end   # ENOENT/EACCES on helper exec
  class HelperCrashError             < Error; end   # signal kill or unknown failure
end
```

Mirrors `rb-speech-mac/lib/speech_mac/errors.rb` patterns; exit code → error class mapping in `HelperClient`.

## Architecture

```
[caller (Ruby)]
  │
  ▼
lib/translation_mac.rb                  ← module entry, helper_path getter/setter
  │
  ├─ require_relative "translation_mac/translation_mac"   (.bundle, lightweight tier)
  │   └─ TranslationMac.supported_languages, .status
  │
  ├─ require_relative "translation_mac/result"            (Data class declarations)
  ├─ require_relative "translation_mac/errors"
  └─ require_relative "translation_mac/helper_client"
      └─ TranslationMac.translate, .prepare
          → Open3.capture3 → ext/.../TranslationMacHelper
                              └─ NSApplication + SwiftUI hosting
                                 └─ NSHostingView(rootView: TranslateView)
                                    └─ .translationTask(config) { session in
                                          try await session.translate(text)
                                       }
```

## File layout

```
rb-translation-mac/
├── lib/
│   └── translation_mac.rb
│   └── translation_mac/
│       ├── version.rb
│       ├── errors.rb
│       ├── result.rb
│       ├── helper_client.rb
│       ├── translation_mac.bundle              (built artifact, .gitignore)
│       └── TranslationMacHelper                (built artifact, .gitignore)
├── ext/
│   └── translation_mac/
│       ├── extconf.rb                          # SwiftGem::Mkmf.create_swift_makefile + helper build/codesign
│       ├── Package.swift                       # 2 targets: TranslationMac (lib), TranslationMacHelper (executable)
│       ├── Resources/
│       │   └── Info.plist                      # CFBundleIdentifier only (no TCC strings)
│       ├── translation_mac.c                   # Init_translation_mac (rb_define_singleton_method × 2)
│       ├── translation_mac.h
│       └── Sources/
│           ├── TranslationMac/                 # lightweight tier
│           │   ├── TranslationMacBridge.swift  # @_cdecl: translation_mac_supported_languages, _status
│           │   └── TranslationMac.swift        # LanguageAvailability wrapper
│           └── TranslationMacHelper/           # heavy tier
│               ├── main.swift                  # argv parser, exit code mapping
│               ├── HelperApp.swift             # NSApplication.shared + .accessory + NSWindow + NSHostingView
│               └── TranslateView.swift         # SwiftUI View with .translationTask
├── test/
│   ├── test_helper.rb
│   ├── translation_mac/
│   │   ├── language_availability_test.rb       # lightweight tier (always run)
│   │   ├── translate_test.rb                   # heavy tier (CI_SKIP gated)
│   │   └── prepare_test.rb                     # heavy tier (CI_SKIP gated)
│   └── fixtures/
│       └── fake_helper.sh                      # for HelperClient unit tests
├── Rakefile
├── Gemfile
├── translation_mac.gemspec
├── example.rb
├── README.md
└── CLAUDE.md
```

## Helper subprocess design

### CLI signature

```
TranslationMacHelper translate <from> <to> <text>
TranslationMacHelper prepare <from> <to>
```

### Exit codes

- `0` — success (text on stdout / "installed" status)
- `2` — `ModelNotInstalledError` (lightweight `LanguageAvailability.status` check at startup short-circuits before sheet)
- `3` — `UnsupportedLanguagePairError`
- `4` — `TimeoutError` (default 30s)
- `5` — generic crash (exception thrown inside helper)
- killed-by-signal → `HelperCrashError` (`status.exitstatus.nil?`)

### Threading model

1. `main.swift` — parse argv, instantiate `HelperApp`, call `app.run()`.
2. `HelperApp.run()`:
   - `NSApplication.shared.setActivationPolicy(.accessory)` (no Dock icon)
   - Create hidden `NSWindow` (zero-size, off-screen)
   - Embed `NSHostingView(rootView: TranslateView(args: ..., onComplete: { ... NSApplication.shared.terminate(...) }))`
   - `NSApplication.shared.run()` — runs the main run loop until `terminate` is called
3. `TranslateView`:
   - On appear, set `@State configuration = TranslationSession.Configuration(source: from, target: to)`
   - `.translationTask(configuration) { session in try await session.translate(text); print(response.targetText); onComplete(0) }`
4. Timeout: `DispatchSourceTimer` in `HelperApp` calls `onComplete(4)` if not finished in 30s.

### Why SwiftUI hosting in a CLI works

`NSHostingView` is the AppKit ↔ SwiftUI bridge. It runs SwiftUI's render/effect cycle inside `NSApplication.shared.run()`. The `.translationTask` modifier hooks into the SwiftUI lifecycle, which the run loop ticks. The window need not be visible — it just needs to be in the view hierarchy.

### Codesign

Same approach as `rb-speech-mac` (codesign with stable bundle identifier). Even without TCC, the helper benefits from a stable identifier so macOS can attach state (e.g., language model download cache) consistently.

## Bundle install / language model download integration

### Rakefile

```ruby
require "bundler/gem_tasks"
require "rake/extensiontask"
require "rake/testtask"

Rake::ExtensionTask.new("translation_mac") do |ext|
  ext.lib_dir = "lib/translation_mac"
end

Rake::TestTask.new(:test) do |t|
  t.libs = %w[lib test]
  t.pattern = "test/**/*_test.rb"
end

namespace :translation_mac do
  desc "Pre-download language models for default pairs (en-US ↔ ja-JP)"
  task prepare_models: :compile do
    if ENV["CI_SKIP"]
      puts "translation_mac:prepare_models — skipped (CI_SKIP set)"
      next
    end

    pairs = ENV.fetch("TRANSLATION_MAC_PAIRS", "en-US:ja-JP,ja-JP:en-US").split(",")
    require_relative "lib/translation_mac"
    pairs.each do |pair|
      from, to = pair.split(":")
      result = TranslationMac.prepare(from: from, to: to)
      puts "  #{from} → #{to}: #{result.success ? 'ready' : "FAILED (#{result.error&.class&.name})"}"
    end
  end
end

task default: %w[compile translation_mac:prepare_models test]
task test: :compile
```

### Bundle install hook

The default `extconf.rb` from `swift_gem` runs only the `Rake::ExtensionTask` (i.e. `rake compile`). To run `prepare_models` automatically on `bundle install`, the gemspec's `extensions` directive points to `extconf.rb`, and we extend `extconf.rb` to invoke `system("rake translation_mac:prepare_models")` after the Makefile is generated.

**Trade-off**: This may trigger a system language model download dialog during `bundle install`. README must document this clearly. CI can opt out via `CI_SKIP=1`.

### Default language pairs

`en-US ↔ ja-JP` (bidirectional), confirmed by user 2026-05-02.

## macOS version requirement

- `Package.swift`: `platforms: [.macOS(.v14)]`
- `gemspec`: no enforcement (no clean way), document in README
- README "Requirements" section to state macOS 14.4+

## Test strategy

### Lightweight tier (always run)

`test/translation_mac/language_availability_test.rb`:

```ruby
class LanguageAvailabilityTest < Test::Unit::TestCase
  def test_supported_languages_includes_english_and_japanese
    langs = TranslationMac.supported_languages
    assert_kind_of Array, langs
    assert(langs.any? { |l| l.start_with?("en") })
    assert(langs.any? { |l| l.start_with?("ja") })
  end

  def test_status_returns_known_symbol
    status = TranslationMac.status(from: "en-US", to: "ja-JP")
    assert_includes [:installed, :supported, :unsupported], status
  end
end
```

### Heavy tier (skipped if `ENV["CI_SKIP"]`)

```ruby
class TranslateTest < Test::Unit::TestCase
  def setup
    omit("CI_SKIP set") if ENV["CI_SKIP"]
    omit("model not installed") unless TranslationMac.status(from: "en-US", to: "ja-JP") == :installed
  end

  def test_translate_english_to_japanese
    result = TranslationMac.translate("Hello", from: "en-US", to: "ja-JP")
    assert_true result.success
    refute_nil result.text
    refute_empty result.text
  end
end
```

`fake_helper.sh` enables `HelperClient` unit tests with controlled exit codes / stdouts (matches rb-speech-mac pattern).

## Decisions log

| # | Question | Decision | Rationale |
|---|---|---|---|
| 1 | Result type or plain return? | **H2: Result type** for heavy tier, plain for lightweight | Helper failure modes (model missing, unsupported, timeout, crash) need to be distinguishable. Lightweight tier is single-failure-mode so plain is fine. |
| 2 | Default language pairs for `prepare_models` | `en-US ↔ ja-JP` bidirectional | User default; project context is JP-EN heavy. |
| 3 | CI skip mechanism | `ENV["CI_SKIP"]` (any truthy) | Per user; not `ENV["CI"]` because user wants explicit opt-in. |
| 4 | One gem with two tiers vs split into two gems | One gem, two tiers | Sharing namespace and lifecycle simpler; users see a single API. |
| 5 | macOS version | `.macOS(.v14)` (14.4+) | Translation framework requirement, no workaround. |

## Out of scope (YAGNI)

- Streaming / batch translate (`translate(batch:)`) — add only on demand
- Auto language detection — exposed by Translation framework but adds complexity; defer
- Custom language model selection — not exposed by Apple's API anyway
- Cross-platform support (iOS, etc.) — gem name suffix `-mac` makes scope explicit
- Concurrent `translate` calls — helper is single-shot subprocess; concurrent callers spawn parallel helpers (OS-managed)

## Prohibitions

- No Python (per global CLAUDE.md)
- No Gemfile.lock in git (library convention)
- Commit messages in English, conventional commits style
- Do not log or persist translated text
- Do not promise determinism of translation results — Apple may update models
- `.claude/` is committed
