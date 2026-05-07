# translation_mac-locale

Locale-aware easy-to-use layer over [rb-translation-mac](https://github.com/bash0C7/rb-translation-mac).

Logical sub-gem inside the rb-translation-mac repo (`locale/` directory). Path-loaded into consumer Gemfiles, never published independently to rubygems.org.

## What it adds

- **POSIX `LANG` → BCP-47 normalization** — `ja_JP.UTF-8` → `ja-JP`, `fr_FR` → `fr-FR`, `ja` → `ja`.
- **Skip-or-translate decision** — `nil`, `""`, `C`, `POSIX`, and any English locale (`en`, `en-US`, `en_GB`) return `nil` from `detect_target_lang`, so callers branch on truthiness.
- **Per-input result cache** — Mutex-guarded, scoped to a single `Translator` instance.
- **Result-struct unwrapping** — accepts either a plain `String` or the `Result` struct (`#success`, `#text`) returned by `TranslationMac.translate`.
- **Silent degrade** — any provider failure (raised exception, `success: false`, blank text) falls back to the input unchanged. UI hover / popup contexts never crash on a flaky model.

## Usage

```ruby
require "translation_mac/locale"

target = TranslationMac::Locale::Translator.detect_target_lang(ENV["LANG"])
# => "ja-JP" when LANG=ja_JP.UTF-8, nil for English / C / unset

t = TranslationMac::Locale::Translator.new(target_lang: target)
t.translate("Adds the value to the array.")
# => "配列に値を追加します。"

t.active?
# => true when target_lang is set, false otherwise
```

When you want to swap the underlying provider (testing, alternative engines):

```ruby
t = TranslationMac::Locale::Translator.new(
  target_lang: "ja-JP",
  translate_proc: ->(text, from:, to:) { my_other_translator.run(text, src: from, dst: to) }
)
```

The default `translate_proc` is `TranslationMac.translate` from the parent gem.

## Why a separate sub-gem

Consumers of `TranslationMac.translate` repeatedly need:
- to read `LANG` and convert to BCP-47
- to skip translation in English / `C` locales
- to cache results to keep UI snappy
- to never crash a hover/popup on a transient model failure

This sub-gem captures that recipe so it lives once, with tests, instead of being re-implemented in every UI-adjacent gem (e.g. `apple_sdk_mac-irb`'s doc preview).

## License

MIT (same as the parent gem).
