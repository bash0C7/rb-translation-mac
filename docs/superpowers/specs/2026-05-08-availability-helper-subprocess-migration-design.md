# Availability API Helper-Subprocess Migration Design

**Date:** 2026-05-08
**Repo:** `rb-translation-mac`
**Status:** Draft → for user review

## Problem

`TranslationMac.status(from:, to:)` and `TranslationMac.supported_languages` are exposed via an in-process C extension that calls the Swift bridge functions `translation_mac_status` and `translation_mac_supported_languages`. Those Swift functions await `LanguageAvailability` async APIs and bridge async → sync via `DispatchSemaphore.wait()`.

This design assumes the host Ruby process has an active main `RunLoop` / dispatch context that can service the Swift cooperative pool's continuations. Under headless contexts (`bundle exec rake test`, plain `ruby foo.rb`), the calling thread blocks on the semaphore while the Task that would signal it is never scheduled — a classic semaphore deadlock. Empirically the call hangs for 4+ minutes with 0% CPU usage on macOS Darwin 25.4.0.

The same `LanguageAvailability` calls succeed inside `TranslationMacHelper` (the existing subprocess used by `.translate` / `.prepare`) because the Helper runs `NSApp.shared.run()`, providing the main run loop the framework needs.

## Goal

Make `.status` and `.supported_languages` work correctly under any Ruby host (headless rake, IRB / Reline, REPL, scripted automation) by routing them through the existing Helper subprocess pattern that already works for `.translate` / `.prepare`. Remove the in-process Swift / C bridge for these APIs entirely.

## Non-goals

- Adding new translation features beyond status / supported_languages.
- Changing return-type contracts: `.status` keeps returning `Symbol` (`:installed` / `:supported` / `:unsupported`), `.supported_languages` keeps returning `Array<String>` of BCP-47 tags.
- Refactoring `.translate` / `.prepare` paths.
- Improving error semantics beyond preserving the existing silent-degrade-on-failure behaviour.

## Architecture

### Current

```
TranslationMac.translate ──► HelperClient ──► Open3.capture3 ──► TranslationMacHelper (NSApp run loop)
TranslationMac.prepare   ──► HelperClient ──► Open3.capture3 ──► TranslationMacHelper

TranslationMac.status              ──► C ext ──► Swift bridge ──► [✗ hang in headless host]
TranslationMac.supported_languages ──► C ext ──► Swift bridge ──► [✗ hang in headless host]
```

### Proposed

```
TranslationMac.translate           ──┐
TranslationMac.prepare             ──┤
TranslationMac.status              ──┼──► HelperClient ──► Open3.capture3 ──► TranslationMacHelper
TranslationMac.supported_languages ──┘
```

All four APIs share the same subprocess invocation pattern. `LanguageAvailability` calls inside the Helper are serviced by `NSApp.shared.run()`'s main run loop — the missing piece in the in-process variant.

## Helper subprocess extension

### `Operation` enum (TranslationMacHelper)

```swift
enum Operation {
    case translate(from: String, to: String, text: String)
    case prepare(from: String, to: String)
    case status(from: String, to: String)        // NEW
    case supportedLanguages                      // NEW
}
```

### argv layout (TranslationMacHelper main.swift)

```
TranslationMacHelper translate   <from> <to> <text>
TranslationMacHelper prepare     <from> <to>
TranslationMacHelper status      <from> <to>     # NEW
TranslationMacHelper languages                   # NEW
```

### `HelperApp.run` branching

`translate` / `prepare` continue through `TranslateView` (which needs `TranslationSession.Configuration`). `status` / `supportedLanguages` skip `TranslateView` and call `LanguageAvailability` directly inside a `Task` launched on NSApp:

```swift
private func runAvailabilityStatus(from: String, to: String) {
    Task {
        let s = await LanguageAvailability().status(
            from: Locale.Language(identifier: from),
            to:   Locale.Language(identifier: to)
        )
        let str: String
        switch s {
        case .installed:   str = "installed"
        case .supported:   str = "supported"
        case .unsupported: str = "unsupported"
        @unknown default:  str = "unsupported"
        }
        DispatchQueue.main.async {
            print(str)
            exit(0)
        }
    }
}

private func runSupportedLanguages() {
    Task {
        let langs = await LanguageAvailability().supportedLanguages
        let lines = langs.map { $0.maximalIdentifier }.joined(separator: "\n")
        DispatchQueue.main.async {
            print(lines)
            exit(0)
        }
    }
}
```

The 30 s timeout currently around `app.run()` is preserved as a global safety net for all four operations.

### Output / exit-code conventions

| Subcommand | exit | stdout                                                      |
|------------|------|-------------------------------------------------------------|
| status     | 0    | `installed` / `supported` / `unsupported` (newline-trimmed) |
| status     | 4    | (timeout — written to stderr)                              |
| status     | 5    | (Apple framework error — message to stderr)                |
| languages  | 0    | newline-separated BCP-47 tags (or empty for empty list)    |
| languages  | 4    | (timeout — written to stderr)                              |
| languages  | 5    | (Apple framework error — message to stderr)                |

These mirror the existing translate / prepare exit-code grammar so HelperClient's `error_for` mapping can be reused unchanged.

## Ruby-side API (lib/translation_mac.rb)

```ruby
require_relative "translation_mac/version"
require_relative "translation_mac/errors"
require_relative "translation_mac/result"
require_relative "translation_mac/helper_client"
# require_relative "translation_mac/translation_mac"  ← REMOVED

module TranslationMac
  DEFAULT_HELPER_PATH = File.expand_path("translation_mac/TranslationMacHelper", __dir__)

  class << self
    def helper_path
      @helper_path ||= DEFAULT_HELPER_PATH
    end
    attr_writer :helper_path

    def translate(text, from:, to:)
      HelperClient.new(helper_path).translate(text, from: from, to: to)
    end

    def prepare(from:, to:)
      HelperClient.new(helper_path).prepare(from: from, to: to)
    end

    def status(from:, to:)                        # NEW
      HelperClient.new(helper_path).status(from: from, to: to)
    end

    def supported_languages                       # NEW
      HelperClient.new(helper_path).supported_languages
    end
  end
end
```

## HelperClient extension (lib/translation_mac/helper_client.rb)

Two new methods preserve the silent-degrade-on-failure contract of the existing C-bridge implementation:

```ruby
def status(from:, to:)
  stdout, _stderr, status = run("status", from, to)
  if status.exitstatus&.zero?
    case stdout.strip
    when "installed"   then :installed
    when "supported"   then :supported
    when "unsupported" then :unsupported
    else :unsupported
    end
  else
    :unsupported
  end
rescue Errno::ENOENT, Errno::EACCES
  :unsupported
end

def supported_languages
  stdout, _stderr, status = run("languages")
  return [] unless status.exitstatus&.zero?
  return [] if stdout.strip.empty?
  stdout.split("\n").map(&:strip).reject(&:empty?)
rescue Errno::ENOENT, Errno::EACCES
  []
end
```

`run` is the existing `Open3.capture3(@helper_path, *args)` wrapper.

## Files removed (Phase D cleanup)

| File / config                                                                       | Action          |
|-------------------------------------------------------------------------------------|-----------------|
| `ext/translation_mac/translation_mac.c`                                             | Delete          |
| `ext/translation_mac/Sources/TranslationMac/TranslationMacBridge.swift`             | Delete          |
| `ext/translation_mac/Sources/TranslationMac/TranslationMac.swift`                   | Delete          |
| `ext/translation_mac/extconf.rb`                                                    | Delete          |
| `ext/translation_mac/Package.swift`                                                 | Drop the `TranslationMac` library product / target; keep `TranslationMacHelper` executable target |
| `translation_mac.gemspec`                                                           | Remove `spec.extensions` array                                                                    |
| `Rakefile`                                                                          | Remove `Rake::ExtensionTask` block                                                                |
| `lib/translation_mac/translation_mac.bundle`                                        | Build artifact — drops out of build naturally; remove from packaged `files` list                 |
| `lib/translation_mac.rb` line 6 (`require_relative "translation_mac/translation_mac"`) | Delete                                                                                            |

## Test strategy

### Unit (FakeHelperSupport)

Add to `test/translation_mac/helper_client_test.rb`:

- `status` exit 0 stdout=`installed` → `:installed`
- `status` exit 0 stdout=`supported` → `:supported`
- `status` exit 0 stdout=`unsupported` → `:unsupported`
- `status` exit 0 stdout=`bogus` → `:unsupported` (silent degrade)
- `status` exit 5 → `:unsupported` (helper crash → degrade)
- `status` missing-binary path → `:unsupported` (HelperSpawnError → degrade)
- `supported_languages` exit 0 stdout=`en-US\nja-JP\n` → `["en-US", "ja-JP"]`
- `supported_languages` exit 0 empty stdout → `[]`
- `supported_languages` exit 5 → `[]`
- `supported_languages` missing-binary → `[]`

### Integration (real Helper)

`test/translation_mac/language_availability_test.rb` (3 existing tests) + `test/translation_mac/translate_test.rb` (1 test, `.status` in setup) + `test/translation_mac/prepare_test.rb` (2 tests, `.status` in body) all become reachable in headless contexts. They serve as the canonical regression battery for the migration: the suite that previously hung in `bundle exec rake test` should now complete without omits beyond CI-skips.

`translation_mac-locale` sub-gem tests (`locale/test/translator_test.rb`, 20 tests) are unchanged and continue to pass.

## TDD commit order (t-wada style)

| # | Phase | Type | Subject                                                                                           |
|---|-------|------|---------------------------------------------------------------------------------------------------|
| 1 | A     | RED  | `test: failing spec for HelperClient#status with FakeHelperSupport`                               |
| 2 | A     | GREEN| `feat: HelperClient#status delegates to helper subprocess`                                        |
| 3 | A     | RED  | `test: failing spec for HelperClient#supported_languages`                                         |
| 4 | A     | GREEN| `feat: HelperClient#supported_languages delegates to helper subprocess`                           |
| 5 | B     | RED  | `test: failing spec for direct Helper status / languages subcommand invocation`                   |
| 6 | B     | GREEN| `feat: Helper supports status / languages subcommands via direct LanguageAvailability path`       |
| 7 | C     | GREEN| `refactor: route TranslationMac.{status,supported_languages} through HelperClient`                |
| 8 | D     | chore| `chore: remove obsolete C extension and Swift in-process bridge`                                  |

Step 7 follows the CLAUDE.md "既存テスト網羅 → RED 省略可" rule: the existing `language_availability_test.rb` covers the change. Verify RED-on-removal explicitly (running suite without C ext should produce `NoMethodError` on `TranslationMac.status`) before applying GREEN.

## Risk / reversibility

| Phase | Reversibility           | Risk   | Notes                                                                       |
|-------|-------------------------|--------|-----------------------------------------------------------------------------|
| A     | trivial (Ruby only)     | low    | FakeHelperSupport pattern reused                                            |
| B     | rebuild to revert       | medium | Apple Translation framework availability behaviour                          |
| C     | `git revert` 1 commit   | low    | Ruby module method redefinition                                             |
| D     | `git revert` 1 commit   | low    | Dead code removal                                                           |

## Verification checkpoints

- After Phase A: `bundle exec rake test test/translation_mac/helper_client_test.rb` all GREEN.
- After Phase B: direct invocation `./TranslationMacHelper status en-US ja-JP` returns exit 0 + stdout `installed` (or `supported` if model not yet downloaded).
- After Phase C: full `bundle exec rake test` GREEN under headless detached process — no hang in `language_availability_test`, `translate_test`, or `prepare_test`. **This is the canonical fix-validation moment.**
- After Phase D: `gem build translation_mac.gemspec` succeeds with no native-extension build step; `lib/` no longer contains `translation_mac.bundle`.

## Out of scope for this design

- Performance optimisation of `.status` (subprocess spawn is ~100–300 ms per call; acceptable for current usage patterns).
- Caching of `.status` / `.supported_languages` results inside `TranslationMac` module (consumers like `translation_mac-locale` already cache translation results per Translator instance; status caching is a separate concern).
- Cross-repo coordination back into `rb-apple-sdk-mac/irb` — that gem only consumes `.translate`, so no changes needed there.

## After merge

The original phenomenon — `bundle exec rake test` hanging at `TranslationMac.status` in headless / detached process — should disappear. Future Ruby callers (whether IRB host, rake test, daemon, web server) can rely on `.status` returning a symbol within the Helper's 30-second budget regardless of host run-loop state.
