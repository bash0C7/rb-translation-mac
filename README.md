# rb-translation-mac

Ruby binding for Apple's Translation framework on macOS / Apple Silicon. Calls `LanguageAvailability` and `TranslationSession` from Ruby through the bundled `TranslationMacHelper` subprocess, a Swift Package Manager executable.

## Requirements

- macOS 27+, Apple Silicon
- Xcode 27 (builds run `xcrun swift`)
- Ruby 4.0+, Bundler 4.x

## Installation

Install from source:

```bash
git clone https://github.com/bash0C7/rb-translation-mac.git
cd rb-translation-mac
bundle install
bundle exec rake compile
```

`rake compile` builds `TranslationMacHelper` with `xcrun swift build -c release --package-path ext/translation_mac`, signs it ad hoc, and installs it to `lib/translation_mac/TranslationMacHelper`.

## Usage

```ruby
require "translation_mac"

TranslationMac.supported_languages
# => ["en-Latn-US", "ja-Jpan-JP", "fr-Latn-FR", ...]

TranslationMac.status(from: "en-US", to: "ja-JP")
# => :installed

result = TranslationMac.translate("Hello", from: "en-US", to: "ja-JP")
result.success
# => true
result.text
# => "こんにちは"

result = TranslationMac.prepare(from: "en-US", to: "fr-FR")
result.success
# => true
result.status
# => :installed
```

`supported_languages` returns maximal BCP-47 identifiers (language-script-region) in no particular order. `status`, `translate`, and `prepare` also accept short identifiers such as `"en-US"` and `"ja"`.

`status` returns `:installed` (models downloaded), `:supported` (models not downloaded), or `:unsupported`. It returns `:unsupported`, and `supported_languages` returns `[]`, when the helper fails.

`translate` uses only installed models and never downloads. `prepare` asks macOS to download the models for a pair and presents the system download prompt when they are not installed. Translation output comes from Apple's models and can change with macOS updates.

`translate` returns a `TranslationMac::TranslationResult` and `prepare` returns a `TranslationMac::PrepareResult`. Neither raises; on failure `success` is `false` and `error` is one of:

| Error | Cause |
|---|---|
| `TranslationMac::ModelNotInstalledError` | The models for the pair are not downloaded |
| `TranslationMac::UnsupportedLanguagePairError` | Apple does not support the pair |
| `TranslationMac::TimeoutError` | The helper did not finish within 30 seconds |
| `TranslationMac::HelperSpawnError` | The helper binary is missing or not executable |
| `TranslationMac::HelperCrashError` | The helper was killed by a signal or failed otherwise |

`TranslationMac.helper_path=` points the gem at another helper binary.

## Language models

Download models for language pairs ahead of time:

```bash
bundle exec rake translation_mac:prepare_models
TRANSLATION_MAC_PAIRS=en-US:fr-FR,fr-FR:en-US bundle exec rake translation_mac:prepare_models
```

The default pairs are `en-US:ja-JP,ja-JP:en-US`.

## translation_mac-locale

`locale/` holds the `translation_mac-locale` sub-gem: POSIX `LANG` to BCP-47 conversion, English and `C` locale skipping, a per-input cache, and fallback to the input text on failure. See [locale/README.md](locale/README.md).

## Development

```bash
bundle install
bundle exec rake test
bundle exec rake console
bundle exec ruby example.rb
```

`rake test` validates `sig/translation_mac.rbs`, runs `rake compile`, then runs the tests. `HelperClient` tests use `test/fixtures/fake_helper.sh`; the other tests call the real helper. `CI_SKIP=1 bundle exec rake test` omits the tests that call the helper subcommands directly and the `translate` / `prepare` tests. The `translate` test and the installed-pair `prepare` test omit themselves when `en-US` to `ja-JP` is not installed.

`example.rb` prints the supported languages and the `en-US` to `ja-JP` status, then translates a sentence when the pair is installed.

The `locale/` sub-gem has its own Gemfile:

```bash
cd locale
bundle install
bundle exec rake test
```

## License

MIT.
