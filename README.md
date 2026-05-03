# rb-translation-mac

Ruby native binding for Apple's Translation framework (`LanguageAvailability` + `TranslationSession`).

## Requirements

- macOS 15.0+ — Apple's docs say the Translation framework runs on 14.4+, but `TranslationSession` and `.translationTask` are marked `@available(macOS 15.0, *)` in the SDK, so 14.4 builds will not compile against this gem.
- Ruby 3.2+
- Swift 6.3+
- Bundler 4.x
- Apple Silicon (arm64-darwin) verified; Intel may work but is not tested

## Installation

```ruby
gem "rb-translation-mac"
```

Then:

```sh
bundle install
```

`bundle install` builds the native extension and (unless `CI_SKIP=1`) pre-downloads the default language pair (`en-US` <-> `ja-JP`) via `rake translation_mac:prepare_models`. macOS may show a system download dialog the first time — accept it.

To pre-download other language pairs:

```sh
TRANSLATION_MAC_PAIRS=en-US:fr-FR,fr-FR:en-US bundle exec rake translation_mac:prepare_models
```

## Usage

### Lightweight tier (in-process, fast)

```ruby
require "translation_mac"

TranslationMac.supported_languages
# => ["en-Latn-GB", "ja-Jpan-JP", "zh-Hans-CN", ...]
# Identifiers are returned in BCP-47 maximal form (Locale.Language#maximalIdentifier),
# i.e. lang-script-region. status(from:, to:) accepts the short form ("en-US", "ja-JP")
# as well, since macOS normalizes internally.

TranslationMac.status(from: "en-US", to: "ja-JP")
# => :installed | :supported | :unsupported
```

### Heavy tier (helper subprocess)

```ruby
result = TranslationMac.translate("Hello", from: "en-US", to: "ja-JP")
result.success    # => true
result.text       # => "こんにちは" (Apple may update models; exact output not guaranteed)

result = TranslationMac.prepare(from: "en-US", to: "fr-FR")
result.success    # => true
result.status     # => :installed
```

Both `translate` and `prepare` return Result objects (`TranslationMac::TranslationResult`, `TranslationMac::PrepareResult`). On failure, `result.error` is one of:

- `TranslationMac::ModelNotInstalledError` — language model not yet downloaded
- `TranslationMac::UnsupportedLanguagePairError` — pair not supported by Apple
- `TranslationMac::TimeoutError` — helper exceeded 30s
- `TranslationMac::HelperSpawnError` — helper binary missing or not executable
- `TranslationMac::HelperCrashError` — helper killed by signal or unknown failure

## Why a helper subprocess?

Apple's `TranslationSession` is delivered exclusively through the SwiftUI `.translationTask` modifier — it cannot be instantiated directly. To call it from Ruby (or any non-SwiftUI context), `rb-translation-mac` ships a small helper binary that hosts a SwiftUI view inside `NSApplication.shared` and forwards results over stdout. `LanguageAvailability` is SwiftUI-independent and ships as a normal Ruby C extension (`.bundle`).

## Development

```sh
bundle install
bundle exec rake test         # full test suite
bundle exec rake compile      # native ext + helper build
bundle exec rake console      # IRB with TranslationMac preloaded
bundle exec ruby example.rb   # smoke-test script (supported_languages, status, translate)
```

In `test/`, the integration tests for `translate` and `prepare` are gated by `CI_SKIP`. Set `CI_SKIP=1` in CI to skip them.

### Running tests in CI

`CI_SKIP=1 bundle exec rake test` skips the `translate`/`prepare` integration tests so CI does not hang on omitted language-model downloads. The lightweight-tier and HelperClient unit tests still run. Use the same flag with `bundle install` to suppress the post-install `prepare_models` download:

```sh
CI_SKIP=1 bundle install
CI_SKIP=1 bundle exec rake test
```

## Related projects

- [bash0C7/swift_gem](https://github.com/bash0C7/swift_gem) — scaffolding gem for Swift-extension Ruby gems
- [bash0C7/rb-vision-ocrmac](https://github.com/bash0C7/rb-vision-ocrmac) — Vision (OCR) sibling
- [bash0C7/rb-vision-mac](https://github.com/bash0C7/rb-vision-mac) — Vision (faces, etc.) sibling
- [bash0C7/rb-natural-language-mac](https://github.com/bash0C7/rb-natural-language-mac) — NaturalLanguage sibling
- [bash0C7/rb-speech-mac](https://github.com/bash0C7/rb-speech-mac) — Speech sibling (also uses helper subprocess pattern)
- [bash0C7/rb-sound-analysis-mac](https://github.com/bash0C7/rb-sound-analysis-mac) — SoundAnalysis sibling

## License

MIT.
