# Changelog

## 0.2.0 — 2026-05-08

Major architectural simplification: all four `TranslationMac` APIs now route through the existing `TranslationMacHelper` subprocess. The in-process C extension and Swift bridge are removed entirely; the gem becomes pure-Ruby (a Helper Swift binary still ships, built by the new `:helper_build` rake task).

### Breaking

- `TranslationMac.status(from:, to:)` and `TranslationMac.supported_languages` no longer execute via the in-process Swift bridge. Public Ruby contract (`Symbol` / `Array<String>` return types, silent-degrade on failure) is unchanged.
- The C extension (`ext/translation_mac/translation_mac.c`, `Sources/TranslationMac/*.swift`, `extconf.rb`) is deleted. Anyone embedding the gem and reaching into private C-bridge symbols will be affected; the public Ruby surface is intact.
- `Rake::ExtensionTask` is removed from the Rakefile. `rake compile` is replaced by `rake helper_build`. `rake test` now depends on `:helper_build` instead of `:compile`.
- The runtime dependency on `swift_gem` is dropped (it was only used by `extconf.rb`).

### Fixed

- Headless `bundle exec rake test` no longer hangs at `TranslationMac.status` waiting for `LanguageAvailability` async continuations. The Helper subprocess provides `NSApplication.shared.run()` which services the async dispatch correctly. Verified end-to-end: previously 4+ minute hang → now 3 seconds.
- `Rakefile :helper_build` is now content-hash-idempotent (skips swift build + codesign + install when source bytes haven't changed).
- `detect_codesign_identity` warns when multiple Apple Development certs are detected and points the user at `TRANSLATION_MAC_CODESIGN_IDENTITY`, restoring the diagnostic the deleted extconf.rb used to emit.

### Added

- `TranslationMac::Locale::Translator.detect_target_lang_priority(*env_values)` — multi-source priority resolution helper for consumers that want a primary env var (`MYTOOL_LANG`, `APPLE_SDK_DOC_LANG`, ...) layered on top of POSIX `LANG`. Lives in the `translation_mac-locale` sub-gem.

### Reference

- Migration design: `docs/superpowers/specs/2026-05-08-availability-helper-subprocess-migration-design.md`
- Implementation plan: `docs/superpowers/plans/2026-05-08-availability-helper-subprocess-migration-plan.md`
