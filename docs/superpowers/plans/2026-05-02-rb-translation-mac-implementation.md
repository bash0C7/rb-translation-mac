# rb-translation-mac Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `rb-translation-mac` Ruby gem per the approved spec at `docs/superpowers/specs/2026-05-02-rb-translation-mac-design.md`. Wraps Apple's Translation framework via two-tier architecture: lightweight `.bundle` (LanguageAvailability) + helper subprocess with SwiftUI hosting (TranslationSession).

**Architecture:** SwiftPM package with two targets — library `TranslationMac` (built as `.bundle`, loaded by Ruby C ext) and executable `TranslationMacHelper` (spawned via Open3). Helper uses `NSApplication` + `NSHostingView` to host a `SwiftUI.View` whose `.translationTask` modifier delivers a `TranslationSession`. Result types via `Data.define`. Bundle-install-time language model preload via Rake task gated by `ENV["CI_SKIP"]`.

**Tech Stack:** Ruby 3.2+, Swift 6.3+ (SE-0495 `@c`), SwiftPM, Apple Translation framework (macOS 15.0+), `swift_gem` 6.3 for the C/Swift bridging (`SwiftGem::Mkmf.create_swift_makefile` — generates auto `<Module>-Swift.h`), `test-unit` for tests, `rake-compiler` for ext build. Helper executable target runs in Swift 5 language mode (`swiftSettings: [.swiftLanguageMode(.v5)]`) to bypass strict-concurrency conflicts with main-actor-isolated `TranslationSession`.

---

## File Structure (final state)

Files **created** by this plan:
- `lib/translation_mac/errors.rb` — Error classes
- `lib/translation_mac/result.rb` — `TranslationResult` / `PrepareResult` Data classes
- `lib/translation_mac/helper_client.rb` — Open3 wrapper, exit-code → error mapping
- `ext/translation_mac/Resources/Info.plist` — helper bundle id
- `ext/translation_mac/Sources/TranslationMacHelper/main.swift` — argv parser, exit code dispatch
- `ext/translation_mac/Sources/TranslationMacHelper/HelperApp.swift` — `NSApplication` + `NSHostingView` + timeout
- `ext/translation_mac/Sources/TranslationMacHelper/TranslateView.swift` — SwiftUI view with `.translationTask`
- `test/fixtures/fake_helper.sh` — env-driven shell stub for HelperClient unit tests
- `test/translation_mac/language_availability_test.rb`
- `test/translation_mac/helper_client_test.rb`
- `test/translation_mac/translate_test.rb` (CI_SKIP gated)
- `test/translation_mac/prepare_test.rb` (CI_SKIP gated)
- `example.rb`
- `CLAUDE.md`

Files **modified** by this plan:
- `ext/translation_mac/Package.swift` — `.macOS(.v15)` + 2-product (library + executable) layout
- `ext/translation_mac/extconf.rb` — append helper build/codesign/install rules to the swift_gem-generated Makefile
- `ext/translation_mac/Sources/TranslationMac/TranslationMac.swift` — replace echo skeleton with LanguageAvailability wrapper
- `ext/translation_mac/Sources/TranslationMac/TranslationMacBridge.swift` — replace echo wrapper with three `@c` (SE-0495) functions: `translation_mac_supported_languages`, `translation_mac_status`, `translation_mac_free`
- `ext/translation_mac/translation_mac.c` — replace echo with two singleton methods (`supported_languages`, `status`); `#include "TranslationMac-Swift.h"` (auto-generated, gitignored)
- `lib/translation_mac.rb` — wire up errors, result, helper_client; expose `translate` / `prepare` / `helper_path`
- `Rakefile` — add `translation_mac:prepare_models` task
- `rb-translation-mac.gemspec` — fix summary/description, leave extensions as-is
- `README.md` — full rewrite (mirrors rb-vision-ocrmac README)
- `test/test_helper.rb` — add `FakeHelperSupport` module

Files **deleted** by this plan:
- `test/translation_mac/sample_test.rb` — scaffold echo test, replaced by real tests

---

## Task 1: Adjust scaffold for Translation framework + tighten gemspec

**Why first:** Establishes macOS 15.0 baseline, Swift package structure (two targets), and a clean gemspec/README before any test/impl is written.

**Files:**
- Modify: `ext/translation_mac/Package.swift`
- Modify: `rb-translation-mac.gemspec`
- Delete: `examples/translation_mac.swift` (we won't ship a Swift example here; example.rb is sufficient)

- [ ] **Step 1.1:** Replace `ext/translation_mac/Package.swift` with two-target layout

```swift
// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "TranslationMac",
    platforms: [.macOS(.v15)],
    products: [
        .library(
            name: "TranslationMac",
            type: .dynamic,
            targets: ["TranslationMac"]
        ),
        .executable(
            name: "TranslationMacHelper",
            targets: ["TranslationMacHelper"]
        ),
    ],
    targets: [
        .target(
            name: "TranslationMac"
        ),
        .executableTarget(
            name: "TranslationMacHelper",
            path: "Sources/TranslationMacHelper",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist",
                ])
            ]
        ),
    ]
)
```

- [ ] **Step 1.2:** Update gemspec summary/description

In `rb-translation-mac.gemspec`, replace the two lines:
```ruby
spec.summary = "Swift-backed native Ruby extension: rb-translation-mac"
spec.description = "rb-translation-mac wraps a Swift implementation as a Ruby native extension via Swift Package Manager and a thin C bridge. Edit this description before publishing."
```
with:
```ruby
spec.summary = "Ruby binding for Apple's Translation framework (LanguageAvailability + TranslationSession via SwiftUI helper)"
spec.description = "rb-translation-mac wraps Apple's Translation framework as a Ruby native extension. The lightweight tier (LanguageAvailability) ships as a .bundle; the heavy tier (TranslationSession) runs in a helper subprocess that hosts SwiftUI to satisfy the framework's UI requirement. Requires macOS 15.0+."
```

- [ ] **Step 1.3:** Delete `examples/translation_mac.swift` and the `examples/` directory if empty

```bash
rm -f examples/translation_mac.swift
rmdir examples 2>/dev/null || true
```

- [ ] **Step 1.4:** Smoke compile to confirm SwiftPM can still resolve the new layout

```bash
bundle install
bundle exec rake clean clobber compile
```

Expected: builds successfully (the executable target builds even though its sources don't exist yet — wait, they DO need to exist; we'll create empty placeholders here so compile passes).

If compile fails because Sources/TranslationMacHelper does not exist, run:
```bash
mkdir -p ext/translation_mac/Sources/TranslationMacHelper ext/translation_mac/Resources
cat > ext/translation_mac/Sources/TranslationMacHelper/main.swift <<'SWIFT'
// Placeholder; real entry point arrives in Task 6.
exit(0)
SWIFT
cat > ext/translation_mac/Resources/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.bash0c7.rb-translation-mac.helper</string>
    <key>CFBundleName</key>
    <string>TranslationMacHelper</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
</dict>
</plist>
PLIST
bundle exec rake clean clobber compile
```

Expected: compile succeeds. The `.bundle` lives at `lib/translation_mac/translation_mac.bundle`.

- [ ] **Step 1.5:** Commit

```bash
git add ext/translation_mac/Package.swift \
         ext/translation_mac/Sources/TranslationMacHelper \
         ext/translation_mac/Resources/Info.plist \
         rb-translation-mac.gemspec
git rm -r examples 2>/dev/null || true
git commit -m "chore: configure SwiftPM for two-target (lib + helper) layout on macOS 15"
```

---

## Task 2: Errors and Result types (Ruby)

**Why now:** Future tests reference these types; lock the public surface first.

**Files:**
- Create: `lib/translation_mac/errors.rb`
- Create: `lib/translation_mac/result.rb`
- Modify: `lib/translation_mac.rb`

- [ ] **Step 2.1:** Create `lib/translation_mac/errors.rb`

```ruby
# frozen_string_literal: true

module TranslationMac
  class Error < StandardError; end
  class ModelNotInstalledError       < Error; end
  class UnsupportedLanguagePairError < Error; end
  class TimeoutError                 < Error; end
  class HelperSpawnError             < Error; end
  class HelperCrashError             < Error; end
end
```

- [ ] **Step 2.2:** Create `lib/translation_mac/result.rb`

```ruby
# frozen_string_literal: true

module TranslationMac
  TranslationResult = Data.define(:text, :success, :error)
  PrepareResult     = Data.define(:status, :success, :error)
end
```

- [ ] **Step 2.3:** Update `lib/translation_mac.rb` to require the new files

Replace the entire file contents with:
```ruby
# frozen_string_literal: true

require_relative "translation_mac/version"
require_relative "translation_mac/errors"
require_relative "translation_mac/result"
require_relative "translation_mac/translation_mac"
```

(`Error` is now defined in `errors.rb`, so the inline `class Error < StandardError; end` from the scaffold is removed.)

- [ ] **Step 2.4:** Smoke check

```bash
bundle exec ruby -Ilib -rtranslation_mac -e 'p TranslationMac::TranslationResult; p TranslationMac::PrepareResult; p TranslationMac::ModelNotInstalledError'
```
Expected: prints three class objects, no errors.

- [ ] **Step 2.5:** Commit

```bash
git add lib/translation_mac/errors.rb lib/translation_mac/result.rb lib/translation_mac.rb
git commit -m "feat: define error classes and Result Data types"
```

---

## Task 3: TDD — LanguageAvailability lightweight tier

**RED:** test that fails because methods don't exist.
**GREEN:** Swift + C implementation that passes.
**Files:**
- Delete: `test/translation_mac/sample_test.rb`
- Create: `test/translation_mac/language_availability_test.rb`
- Modify: `ext/translation_mac/Sources/TranslationMac/TranslationMac.swift`
- Modify: `ext/translation_mac/Sources/TranslationMac/TranslationMacBridge.swift`
- Modify: `ext/translation_mac/translation_mac.c` (note: handwritten `.h` no longer exists; auto-generated `TranslationMac-Swift.h` replaces it)

- [ ] **Step 3.1:** Remove the scaffold echo test

```bash
git rm test/translation_mac/sample_test.rb
```

- [ ] **Step 3.2:** Write the failing test at `test/translation_mac/language_availability_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class LanguageAvailabilityTest < Test::Unit::TestCase
  test "supported_languages returns array including English and Japanese tags" do
    langs = TranslationMac.supported_languages
    assert_kind_of(Array, langs)
    assert(langs.any? { |l| l.start_with?("en") }, "expected an en-* tag, got: #{langs.inspect}")
    assert(langs.any? { |l| l.start_with?("ja") }, "expected a ja-* tag, got: #{langs.inspect}")
  end

  test "status returns one of installed / supported / unsupported" do
    status = TranslationMac.status(from: "en-US", to: "ja-JP")
    assert_includes([:installed, :supported, :unsupported], status)
  end

  test "status returns :unsupported for nonsense pair" do
    status = TranslationMac.status(from: "xx-XX", to: "yy-YY")
    assert_equal(:unsupported, status)
  end
end
```

- [ ] **Step 3.3:** Run test, expect failure

```bash
bundle exec rake test TEST=test/translation_mac/language_availability_test.rb
```
Expected: NoMethodError (`undefined method 'supported_languages'`) or compile failure.

- [ ] **Step 3.4:** Replace `ext/translation_mac/Sources/TranslationMac/TranslationMac.swift`

```swift
import Foundation
import Translation

@available(macOS 15.0, *)
private let availability = LanguageAvailability()

@available(macOS 15.0, *)
func translationMacSupportedLanguages() -> String {
    let semaphore = DispatchSemaphore(value: 0)
    var langs: [String] = []
    Task {
        let supported = await availability.supportedLanguages
        langs = supported.map { $0.maximalIdentifier }
        semaphore.signal()
    }
    semaphore.wait()
    return langs.joined(separator: "\n")
}

@available(macOS 15.0, *)
func translationMacStatus(from: String, to: String) -> String {
    let semaphore = DispatchSemaphore(value: 0)
    var result = "unsupported"
    Task {
        let src = Locale.Language(identifier: from)
        let dst = Locale.Language(identifier: to)
        let s = await availability.status(from: src, to: dst)
        switch s {
        case .installed:   result = "installed"
        case .supported:   result = "supported"
        case .unsupported: result = "unsupported"
        @unknown default:  result = "unsupported"
        }
        semaphore.signal()
    }
    semaphore.wait()
    return result
}
```

> Note on `Locale.Language(identifier:)`: BCP-47 tag like `"en-US"`. Apple's API accepts BCP-47 here. If `LanguageAvailability` rejects an unknown identifier, the underlying call still returns `.unsupported`, so the third test case is satisfied.

- [ ] **Step 3.5:** Replace `ext/translation_mac/Sources/TranslationMac/TranslationMacBridge.swift`

> swift_gem 6.3 uses SE-0495 `@c` (no string argument; the Swift function name itself becomes the C export name). The auto-generated `TranslationMac-Swift.h` is emitted by `swift build` during `extconf.rb`.

```swift
import Foundation

@c
public func translation_mac_supported_languages() -> UnsafeMutablePointer<CChar> {
    if #available(macOS 15.0, *) {
        return strdup(translationMacSupportedLanguages())!
    } else {
        return strdup("")!
    }
}

@c
public func translation_mac_status(
    _ from: UnsafePointer<CChar>,
    _ to: UnsafePointer<CChar>
) -> UnsafeMutablePointer<CChar> {
    if #available(macOS 15.0, *) {
        let f = String(cString: from)
        let t = String(cString: to)
        return strdup(translationMacStatus(from: f, to: t))!
    } else {
        return strdup("unsupported")!
    }
}

@c
public func translation_mac_free(_ ptr: UnsafeMutablePointer<CChar>?) {
    free(ptr)
}
```

- [ ] **Step 3.6:** ~~Create handwritten `translation_mac.h`~~ — **DELETED**. swift_gem 6.3 auto-generates `TranslationMac-Swift.h` via `swift build -Xswiftc -emit-clang-header-path` during `extconf.rb` execution. The `.gitignore` already suppresses `ext/**/*-Swift.h`.

- [ ] **Step 3.7:** Replace `ext/translation_mac/translation_mac.c`

```c
#include <ruby.h>
#include "TranslationMac-Swift.h"

static VALUE rb_translation_mac_supported_languages(VALUE self) {
    char *result = translation_mac_supported_languages();
    if (result == NULL) return rb_ary_new();
    VALUE str = rb_utf8_str_new_cstr(result);
    translation_mac_free(result);
    if (RSTRING_LEN(str) == 0) return rb_ary_new();
    return rb_str_split(str, "\n");
}

static VALUE rb_translation_mac_status(int argc, VALUE *argv, VALUE self) {
    VALUE opts;
    rb_scan_args(argc, argv, "0:", &opts);
    if (NIL_P(opts)) rb_raise(rb_eArgError, "expected keyword args from: and to:");
    VALUE from = rb_hash_aref(opts, ID2SYM(rb_intern("from")));
    VALUE to   = rb_hash_aref(opts, ID2SYM(rb_intern("to")));
    if (NIL_P(from) || NIL_P(to)) rb_raise(rb_eArgError, "from: and to: are required");

    const char *c_from = StringValueCStr(from);
    const char *c_to   = StringValueCStr(to);
    char *result = translation_mac_status(c_from, c_to);
    if (result == NULL) return ID2SYM(rb_intern("unsupported"));
    VALUE sym = ID2SYM(rb_intern(result));
    translation_mac_free(result);
    return sym;
}

void Init_translation_mac(void) {
    VALUE module = rb_define_module("TranslationMac");
    rb_define_singleton_method(module, "supported_languages", rb_translation_mac_supported_languages, 0);
    rb_define_singleton_method(module, "status", rb_translation_mac_status, -1);
}
```

- [ ] **Step 3.8:** Build and run tests

```bash
bundle exec rake clean clobber compile
bundle exec rake test TEST=test/translation_mac/language_availability_test.rb
```
Expected: 3 tests pass.

- [ ] **Step 3.9:** Commit (RED + GREEN as one feat commit since the same code change is the test+impl unit)

Per the global TDD discipline note ("RED と GREEN は独立コミットにする"), split into two commits if possible — but here the test cannot run RED at all without `lib/translation_mac.rb` already requiring the .bundle, which it does from scaffold. So:

  - First commit RED:
    ```bash
    git rm test/translation_mac/sample_test.rb
    git add test/translation_mac/language_availability_test.rb
    git commit -m "test: add failing spec for LanguageAvailability supported_languages and status"
    ```
    (Verify it's actually RED by running `bundle exec rake test TEST=test/translation_mac/language_availability_test.rb` before staging — it should fail.)

  - Then GREEN:
    ```bash
    git add ext/translation_mac/Sources/TranslationMac/TranslationMac.swift \
             ext/translation_mac/Sources/TranslationMac/TranslationMacBridge.swift \
             ext/translation_mac/translation_mac.c
    git commit -m "feat: implement LanguageAvailability lightweight tier (supported_languages, status)"
    ```

---

## Task 4: TDD — HelperClient with fake helper

**RED:** comprehensive HelperClient test (mirrors rb-speech-mac) with fake helper.
**GREEN:** HelperClient implementation with exit-code → error mapping.

**Files:**
- Create: `test/fixtures/fake_helper.sh`
- Modify: `test/test_helper.rb`
- Create: `test/translation_mac/helper_client_test.rb`
- Create: `lib/translation_mac/helper_client.rb`
- Modify: `lib/translation_mac.rb`

- [ ] **Step 4.1:** Create `test/fixtures/fake_helper.sh`

```bash
mkdir -p test/fixtures
cat > test/fixtures/fake_helper.sh <<'SH'
#!/bin/sh
# Fake helper for HelperClient tests. Behavior driven by env vars:
#   FAKE_STDOUT — printed to stdout (no trailing newline)
#   FAKE_STDERR — printed to stderr (no trailing newline)
#   FAKE_EXIT   — exit code (default 0)
#   FAKE_SIGNAL — if set (e.g. KILL, TERM), self-signal so the caller observes
#                 a Process::Status with exitstatus == nil
[ -n "$FAKE_STDOUT" ] && printf '%s' "$FAKE_STDOUT"
[ -n "$FAKE_STDERR" ] && printf '%s' "$FAKE_STDERR" >&2
[ -n "$FAKE_SIGNAL" ] && kill -"$FAKE_SIGNAL" $$
exit "${FAKE_EXIT:-0}"
SH
chmod +x test/fixtures/fake_helper.sh
```

- [ ] **Step 4.2:** Replace `test/test_helper.rb` with FakeHelperSupport mixin

```ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "translation_mac"

require "test-unit"

module FakeHelperSupport
  FAKE_HELPER = File.expand_path("fixtures/fake_helper.sh", __dir__)
  FAKE_ENV_KEYS = %w[FAKE_EXIT FAKE_STDOUT FAKE_STDERR FAKE_SIGNAL].freeze

  def setup
    super
    @original_helper_path = TranslationMac.helper_path
    TranslationMac.helper_path = FAKE_HELPER
    FAKE_ENV_KEYS.each { |k| ENV.delete(k) }
  end

  def teardown
    TranslationMac.helper_path = @original_helper_path
    FAKE_ENV_KEYS.each { |k| ENV.delete(k) }
    super
  end
end
```

- [ ] **Step 4.3:** Create `test/translation_mac/helper_client_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class HelperClientTest < Test::Unit::TestCase
  include FakeHelperSupport

  def build_client(exit_code: 0, stdout: "", stderr: "", path: FAKE_HELPER)
    ENV["FAKE_EXIT"]   = exit_code.to_s
    ENV["FAKE_STDOUT"] = stdout
    ENV["FAKE_STDERR"] = stderr
    TranslationMac::HelperClient.new(path)
  end

  # ----- translate -----

  test "translate exit 0 -> TranslationResult(success: true, text: stdout)" do
    client = build_client(exit_code: 0, stdout: "こんにちは")
    result = client.translate("Hello", from: "en-US", to: "ja-JP")
    assert_kind_of(TranslationMac::TranslationResult, result)
    assert_equal(true, result.success)
    assert_equal("こんにちは", result.text)
    assert_nil(result.error)
  end

  test "translate exit 2 -> ModelNotInstalledError" do
    client = build_client(exit_code: 2)
    result = client.translate("Hello", from: "en-US", to: "ja-JP")
    assert_equal(false, result.success)
    assert_nil(result.text)
    assert_kind_of(TranslationMac::ModelNotInstalledError, result.error)
  end

  test "translate exit 3 -> UnsupportedLanguagePairError" do
    client = build_client(exit_code: 3)
    result = client.translate("Hello", from: "en-US", to: "xx-XX")
    assert_kind_of(TranslationMac::UnsupportedLanguagePairError, result.error)
  end

  test "translate exit 4 -> TimeoutError" do
    client = build_client(exit_code: 4)
    result = client.translate("Hello", from: "en-US", to: "ja-JP")
    assert_kind_of(TranslationMac::TimeoutError, result.error)
  end

  test "translate exit 5 -> HelperCrashError with stderr in message" do
    client = build_client(exit_code: 5, stderr: "internal: foo")
    result = client.translate("Hello", from: "en-US", to: "ja-JP")
    assert_kind_of(TranslationMac::HelperCrashError, result.error)
    assert_match(/internal: foo/, result.error.message)
  end

  test "translate unknown exit -> HelperCrashError" do
    client = build_client(exit_code: 99, stderr: "segfault")
    result = client.translate("Hello", from: "en-US", to: "ja-JP")
    assert_kind_of(TranslationMac::HelperCrashError, result.error)
  end

  test "translate with missing helper binary -> HelperSpawnError" do
    client = TranslationMac::HelperClient.new("/nonexistent/__missing_xyz")
    result = client.translate("Hello", from: "en-US", to: "ja-JP")
    assert_kind_of(TranslationMac::HelperSpawnError, result.error)
    assert_equal(false, result.success)
  end

  test "translate with helper killed by signal -> HelperCrashError" do
    ENV["FAKE_SIGNAL"] = "KILL"
    client = TranslationMac::HelperClient.new(FAKE_HELPER)
    result = client.translate("Hello", from: "en-US", to: "ja-JP")
    assert_kind_of(TranslationMac::HelperCrashError, result.error)
    assert_equal(false, result.success)
  end

  # ----- prepare -----

  test "prepare exit 0 stdout=installed -> PrepareResult(:installed, success: true)" do
    client = build_client(exit_code: 0, stdout: "installed")
    result = client.prepare(from: "en-US", to: "ja-JP")
    assert_kind_of(TranslationMac::PrepareResult, result)
    assert_equal(:installed, result.status)
    assert_equal(true, result.success)
    assert_nil(result.error)
  end

  test "prepare exit 3 -> PrepareResult(:unknown, UnsupportedLanguagePairError)" do
    client = build_client(exit_code: 3)
    result = client.prepare(from: "xx-XX", to: "yy-YY")
    assert_equal(:unknown, result.status)
    assert_equal(false, result.success)
    assert_kind_of(TranslationMac::UnsupportedLanguagePairError, result.error)
  end

  test "prepare with missing helper binary -> HelperSpawnError" do
    client = TranslationMac::HelperClient.new("/nonexistent/__missing_xyz")
    result = client.prepare(from: "en-US", to: "ja-JP")
    assert_equal(false, result.success)
    assert_kind_of(TranslationMac::HelperSpawnError, result.error)
  end

  test "prepare with helper killed by signal -> HelperCrashError" do
    ENV["FAKE_SIGNAL"] = "KILL"
    client = TranslationMac::HelperClient.new(FAKE_HELPER)
    result = client.prepare(from: "en-US", to: "ja-JP")
    assert_kind_of(TranslationMac::HelperCrashError, result.error)
  end
end
```

- [ ] **Step 4.4:** Run tests, expect failure

```bash
bundle exec rake test TEST=test/translation_mac/helper_client_test.rb
```
Expected: NameError or NoMethodError (`HelperClient` not defined / `helper_path` not defined).

- [ ] **Step 4.5:** Commit RED

```bash
git add test/fixtures/fake_helper.sh test/test_helper.rb test/translation_mac/helper_client_test.rb
git commit -m "test: add failing spec for HelperClient with fake helper fixture"
```

- [ ] **Step 4.6:** Create `lib/translation_mac/helper_client.rb`

```ruby
# frozen_string_literal: true

require "open3"

module TranslationMac
  class HelperClient
    EXIT_CODE_ERRORS = {
      2 => ModelNotInstalledError,
      3 => UnsupportedLanguagePairError,
      4 => TimeoutError,
    }.freeze

    PREPARE_STATUSES = {
      "installed"   => :installed,
      "supported"   => :supported,
      "unsupported" => :unsupported,
    }.freeze

    def initialize(helper_path)
      @helper_path = helper_path
    end

    def translate(text, from:, to:)
      stdout, stderr, status = run("translate", from, to, text)
      if status.exitstatus&.zero?
        TranslationResult.new(text: stdout, success: true, error: nil)
      else
        TranslationResult.new(text: nil, success: false, error: error_for(status, stderr))
      end
    rescue Errno::ENOENT, Errno::EACCES => e
      TranslationResult.new(text: nil, success: false, error: HelperSpawnError.new(e.message))
    end

    def prepare(from:, to:)
      stdout, stderr, status = run("prepare", from, to)
      sym = PREPARE_STATUSES.fetch(stdout.strip, :unknown)
      if status.exitstatus&.zero?
        PrepareResult.new(status: sym, success: true, error: nil)
      else
        PrepareResult.new(status: :unknown, success: false, error: error_for(status, stderr))
      end
    rescue Errno::ENOENT, Errno::EACCES => e
      PrepareResult.new(status: :unknown, success: false, error: HelperSpawnError.new(e.message))
    end

    private

    def run(*args)
      Open3.capture3(@helper_path, *args)
    end

    def error_for(status, stderr)
      return HelperCrashError.new(crash_message(stderr, status)) if status.exitstatus.nil?
      klass = EXIT_CODE_ERRORS[status.exitstatus]
      return klass.new(stderr) if klass
      HelperCrashError.new(stderr.empty? ? "exit #{status.exitstatus}" : stderr)
    end

    def crash_message(stderr, status)
      return stderr unless stderr.empty?
      sig = status&.termsig
      sig ? "killed by signal #{sig}" : "killed by signal"
    end
  end
end
```

- [ ] **Step 4.7:** Replace `lib/translation_mac.rb` to wire up HelperClient and expose translate/prepare

```ruby
# frozen_string_literal: true

require_relative "translation_mac/version"
require_relative "translation_mac/errors"
require_relative "translation_mac/result"
require_relative "translation_mac/translation_mac"
require_relative "translation_mac/helper_client"

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
  end
end
```

- [ ] **Step 4.8:** Run tests, expect pass

```bash
bundle exec rake test TEST=test/translation_mac/helper_client_test.rb
```
Expected: 12 tests, 0 failures.

- [ ] **Step 4.9:** Commit GREEN

```bash
git add lib/translation_mac/helper_client.rb lib/translation_mac.rb
git commit -m "feat: implement HelperClient with exit-code -> error mapping"
```

---

## Task 5: Resources/Info.plist + extconf.rb codesign helper integration

**Why now:** Need the helper Makefile rules in place before TaskMacHelper sources can be built and tested.

**Files:**
- Modify: `ext/translation_mac/Resources/Info.plist` (already created as placeholder in Task 1.4 — no changes needed if content matches; otherwise overwrite)
- Modify: `ext/translation_mac/extconf.rb`

- [ ] **Step 5.1:** Confirm `ext/translation_mac/Resources/Info.plist` matches:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.bash0c7.rb-translation-mac.helper</string>
    <key>CFBundleName</key>
    <string>TranslationMacHelper</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
</dict>
</plist>
```

(No `NSTranslationUsageDescription` — Translation framework is not TCC-gated.)

- [ ] **Step 5.2:** Replace `ext/translation_mac/extconf.rb`

```ruby
# frozen_string_literal: true

require "swift_gem/mkmf"

BUNDLE_ID  = "com.bash0c7.rb-translation-mac.helper"
HELPER_BIN = ".build/release/TranslationMacHelper"

def detect_codesign_identity
  override = ENV["TRANSLATION_MAC_CODESIGN_IDENTITY"]
  return override if override && !override.empty?

  output = `security find-identity -v -p codesigning 2>/dev/null`
  candidates = output.scan(/"(Apple Development:[^"]+)"/).flatten
  case candidates.size
  when 0
    "-"
  when 1
    candidates.first
  else
    warn "[rb-translation-mac] multiple Apple Development certs found:"
    candidates.each { |c| warn "[rb-translation-mac]   #{c}" }
    warn "[rb-translation-mac] using first; set TRANSLATION_MAC_CODESIGN_IDENTITY to choose"
    candidates.first
  end
end

def make_escape(string)
  string.gsub("$", "$$")
end

# 1. Let swift_gem build the lightweight tier (.bundle)
SwiftGem::Mkmf.create_swift_makefile(
  "translation_mac/translation_mac",
  package: "TranslationMac",
  source_dir: __dir__
)

# 2. Append helper build/codesign/install rules to the generated Makefile.
source_dir   = __dir__
gem_root     = File.expand_path("../..", source_dir)
helper_dest  = File.join(gem_root, "lib", "translation_mac", "TranslationMacHelper")
helper_dir   = File.dirname(helper_dest)
identity     = detect_codesign_identity

File.open("Makefile", "a") do |f|
  f.puts <<~MAKEFILE

    # ---- helper subprocess (added by extconf.rb) ----
    HELPER_BIN     = #{HELPER_BIN}
    HELPER_DEST    = #{make_escape(helper_dest)}
    HELPER_DEST_DIR= #{make_escape(helper_dir)}
    HELPER_IDENTITY= #{make_escape(identity)}
    HELPER_BUNDLE_ID = #{BUNDLE_ID}

    .PHONY: helper helper_install

    helper:
    \tswift build -c release --package-path #{make_escape(source_dir)} --product TranslationMacHelper
    \tcodesign -s '$(HELPER_IDENTITY)' --force --identifier '$(HELPER_BUNDLE_ID)' --options runtime '#{make_escape(source_dir)}/$(HELPER_BIN)'

    helper_install: helper
    \t@mkdir -p '$(HELPER_DEST_DIR)'
    \tinstall -m 755 '#{make_escape(source_dir)}/$(HELPER_BIN)' '$(HELPER_DEST)'

    install: helper_install
  MAKEFILE
end

puts "[rb-translation-mac] codesign identity: #{identity}"
puts "[rb-translation-mac] helper install:    #{helper_dest}"
```

> The trailing `install: helper_install` line piggy-backs on the standard `mkmf` `install` target so `rake install` runs the helper install after the .bundle install. `make all` from `rake compile` only triggers `all:` (which depends on the .bundle build), so we add `all: helper_install` if needed — verify after Task 6 builds the helper successfully and adjust here if the helper isn't being copied to `lib/translation_mac/`.

- [ ] **Step 5.3:** Smoke compile (helper sources are still placeholder from Task 1.4, so this should still build)

```bash
bundle exec rake clean clobber compile
ls lib/translation_mac/
```
Expected: `translation_mac.bundle` and possibly `TranslationMacHelper` (if `all:` chain wired correctly). If only `.bundle` is present, that's OK — Task 6 will revisit the Makefile to add `all: helper_install`.

- [ ] **Step 5.4:** Commit

```bash
git add ext/translation_mac/extconf.rb ext/translation_mac/Resources/Info.plist
git commit -m "feat: add helper subprocess build/codesign/install rules to extconf"
```

---

## Task 6: TranslationMacHelper Swift sources (SwiftUI hosting)

**Why now:** All Ruby surface is in place; helper completes the heavy tier so integration tests can run.

**Files:**
- Modify: `ext/translation_mac/Sources/TranslationMacHelper/main.swift`
- Create: `ext/translation_mac/Sources/TranslationMacHelper/HelperApp.swift`
- Create: `ext/translation_mac/Sources/TranslationMacHelper/TranslateView.swift`

- [ ] **Step 6.1:** Replace `ext/translation_mac/Sources/TranslationMacHelper/main.swift`

```swift
import Foundation

// argv layout:
//   TranslationMacHelper translate <from> <to> <text>
//   TranslationMacHelper prepare   <from> <to>

let args = CommandLine.arguments

func usage() -> Never {
    FileHandle.standardError.write(Data("usage:\n".utf8))
    FileHandle.standardError.write(Data("  TranslationMacHelper translate <from> <to> <text>\n".utf8))
    FileHandle.standardError.write(Data("  TranslationMacHelper prepare <from> <to>\n".utf8))
    exit(5)
}

guard args.count >= 2 else { usage() }
let command = args[1]

guard #available(macOS 15.0, *) else {
    FileHandle.standardError.write(Data("requires macOS 15.0+\n".utf8))
    exit(3)
}

let app = HelperApp()

switch command {
case "translate":
    guard args.count >= 5 else { usage() }
    app.run(operation: .translate(from: args[2], to: args[3], text: args[4]))
case "prepare":
    guard args.count >= 4 else { usage() }
    app.run(operation: .prepare(from: args[2], to: args[3]))
default:
    usage()
}
```

- [ ] **Step 6.2:** Create `ext/translation_mac/Sources/TranslationMacHelper/HelperApp.swift`

```swift
import AppKit
import SwiftUI

enum Operation {
    case translate(from: String, to: String, text: String)
    case prepare(from: String, to: String)
}

@available(macOS 15.0, *)
final class HelperApp {
    func run(operation: Operation) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        // Off-screen 1x1 borderless window. PoC verified (2026-05-02):
        // - SwiftUI .translationTask fires under NSHostingView in this configuration.
        // - Language model download sheets attach to this window AND macOS promotes
        //   the sheet to the foreground so the user sees it. No visible window required.
        let window = NSWindow(
            contentRect: NSRect(x: -200, y: -200, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false

        let view = TranslateView(operation: operation, onComplete: { exitCode, output, errorMessage in
            DispatchQueue.main.async {
                if let output = output { print(output) }
                if let msg = errorMessage {
                    FileHandle.standardError.write(Data(msg.utf8))
                }
                exit(exitCode)
            }
        })
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)

        // Timeout: 30 s
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            FileHandle.standardError.write(Data("timeout".utf8))
            exit(4)
        }

        app.run()
    }
}
```

- [ ] **Step 6.3:** Create `ext/translation_mac/Sources/TranslationMacHelper/TranslateView.swift`

```swift
import SwiftUI
import Translation

@available(macOS 15.0, *)
struct TranslateView: View {
    let operation: Operation
    let onComplete: (Int32, String?, String?) -> Void

    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                let (from, to) = endpoints()
                configuration = TranslationSession.Configuration(
                    source: Locale.Language(identifier: from),
                    target: Locale.Language(identifier: to)
                )
            }
            .translationTask(configuration) { session in
                await runTask(session: session)
            }
    }

    private func endpoints() -> (String, String) {
        switch operation {
        case .translate(let from, let to, _): return (from, to)
        case .prepare(let from, let to):       return (from, to)
        }
    }

    private func runTask(session: TranslationSession) async {
        do {
            switch operation {
            case .translate(_, _, let text):
                let availability = LanguageAvailability()
                let (from, to) = endpoints()
                let status = await availability.status(
                    from: Locale.Language(identifier: from),
                    to:   Locale.Language(identifier: to)
                )
                switch status {
                case .unsupported: onComplete(3, nil, "unsupported language pair"); return
                case .supported:   onComplete(2, nil, "model not installed"); return
                case .installed:   break
                @unknown default:  onComplete(3, nil, "unknown availability"); return
                }
                let response = try await session.translate(text)
                onComplete(0, response.targetText, nil)
            case .prepare:
                try await session.prepareTranslation()
                onComplete(0, "installed", nil)
            }
        } catch {
            onComplete(5, nil, "\(error)")
        }
    }
}
```

- [ ] **Step 6.4:** Build and smoke test the helper directly

```bash
bundle exec rake clean clobber compile
ls -la lib/translation_mac/
# expect: translation_mac.bundle, TranslationMacHelper

# Direct invocation (assuming en-US ↔ ja-JP model installed):
./lib/translation_mac/TranslationMacHelper translate en-US ja-JP "Hello"
# expect: stdout = "こんにちは" or similar; exit 0
```

If `TranslationMacHelper` was not copied to `lib/translation_mac/`, edit `ext/translation_mac/extconf.rb`'s appended Makefile block and change the line `install: helper_install` to also chain into `all:`:

```makefile
all: helper_install
```

Re-run `bundle exec rake clean clobber compile`.

- [ ] **Step 6.5:** Commit

```bash
git add ext/translation_mac/Sources/TranslationMacHelper/main.swift \
         ext/translation_mac/Sources/TranslationMacHelper/HelperApp.swift \
         ext/translation_mac/Sources/TranslationMacHelper/TranslateView.swift
# (and possibly extconf.rb if Makefile tweak required)
git add ext/translation_mac/extconf.rb 2>/dev/null
git commit -m "feat: implement TranslationMacHelper with NSApplication + SwiftUI hosting"
```

---

## Task 7: Integration tests for translate / prepare with real helper (CI_SKIP gated)

**Files:**
- Create: `test/translation_mac/translate_test.rb`
- Create: `test/translation_mac/prepare_test.rb`

- [ ] **Step 7.1:** Create `test/translation_mac/translate_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class TranslateIntegrationTest < Test::Unit::TestCase
  def setup
    omit("CI_SKIP set") if ENV["CI_SKIP"]
    status = TranslationMac.status(from: "en-US", to: "ja-JP")
    omit("language model en-US -> ja-JP not installed (got #{status})") unless status == :installed
  end

  test "translate English to Japanese returns non-empty text" do
    result = TranslationMac.translate("Hello", from: "en-US", to: "ja-JP")
    assert_kind_of(TranslationMac::TranslationResult, result)
    assert_equal(true, result.success, "error: #{result.error&.message}")
    refute_nil(result.text)
    refute_empty(result.text.strip)
  end
end
```

- [ ] **Step 7.2:** Create `test/translation_mac/prepare_test.rb`

```ruby
# frozen_string_literal: true

require "test_helper"

class PrepareIntegrationTest < Test::Unit::TestCase
  def setup
    omit("CI_SKIP set") if ENV["CI_SKIP"]
  end

  test "prepare for installed pair returns success" do
    status = TranslationMac.status(from: "en-US", to: "ja-JP")
    omit("not installed (got #{status}); skipping to avoid system download dialog") unless status == :installed
    result = TranslationMac.prepare(from: "en-US", to: "ja-JP")
    assert_kind_of(TranslationMac::PrepareResult, result)
    assert_equal(true, result.success, "error: #{result.error&.message}")
  end

  test "prepare for unsupported pair returns UnsupportedLanguagePairError" do
    result = TranslationMac.prepare(from: "xx-XX", to: "yy-YY")
    assert_equal(false, result.success)
    assert_kind_of(TranslationMac::UnsupportedLanguagePairError, result.error)
  end
end
```

- [ ] **Step 7.3:** Run full test suite

```bash
bundle exec rake test
```
Expected: All HelperClient unit tests pass (12), LanguageAvailability tests pass (3), translate/prepare integration tests pass or omit gracefully (2 + 2). No failures, no errors.

- [ ] **Step 7.4:** Commit

```bash
git add test/translation_mac/translate_test.rb test/translation_mac/prepare_test.rb
git commit -m "test: add CI_SKIP-gated integration tests for translate and prepare"
```

---

## Task 8: Rakefile prepare_models task + bundle install hook

**Files:**
- Modify: `Rakefile`
- Modify: `ext/translation_mac/extconf.rb`

- [ ] **Step 8.1:** Replace `Rakefile` with:

```ruby
# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "rake/extensiontask"

Rake::ExtensionTask.new("translation_mac") do |ext|
  ext.lib_dir = "lib/translation_mac"
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

desc "Start an IRB console with translation_mac loaded"
task console: :compile do
  require "irb"
  $LOAD_PATH.unshift File.expand_path("lib", __dir__)
  require "translation_mac"
  ARGV.clear
  IRB.start
end

namespace :translation_mac do
  desc "Pre-download language models (default: en-US <-> ja-JP). Override via TRANSLATION_MAC_PAIRS=en-US:fr-FR,fr-FR:en-US"
  task prepare_models: :compile do
    if ENV["CI_SKIP"]
      puts "translation_mac:prepare_models — skipped (CI_SKIP set)"
      next
    end

    pairs = ENV.fetch("TRANSLATION_MAC_PAIRS", "en-US:ja-JP,ja-JP:en-US").split(",")
    $LOAD_PATH.unshift File.expand_path("lib", __dir__)
    require "translation_mac"
    pairs.each do |pair|
      from, to = pair.split(":")
      result = TranslationMac.prepare(from: from, to: to)
      label = result.success ? "ready (#{result.status})" : "FAILED (#{result.error&.class&.name})"
      puts "  #{from} -> #{to}: #{label}"
    end
  end
end

task test: :compile
task default: :test
```

- [ ] **Step 8.2:** Add bundle-install-time hook to `ext/translation_mac/extconf.rb`

Append at the very end of the `File.open("Makefile", "a")` block (inside the heredoc), just before the closing `MAKEFILE`:

```makefile

# After install, fire prepare_models so first-use is hot.
# Skipped under CI_SKIP=1 (CI environments cannot answer system download dialog).
post_install: install
\t@if [ -z "$$CI_SKIP" ]; then \\
\t\tcd #{make_escape(gem_root)} && bundle exec rake translation_mac:prepare_models || true; \\
\tfi

all: post_install
```

(The `|| true` ensures failures don't break gem install — the user can re-run `rake translation_mac:prepare_models` later.)

- [ ] **Step 8.3:** Verify with CI_SKIP

```bash
CI_SKIP=1 bundle exec rake clean clobber compile
# expect: build succeeds; "translation_mac:prepare_models — skipped (CI_SKIP set)" appears in output
```

- [ ] **Step 8.4:** Verify without CI_SKIP

```bash
bundle exec rake clean clobber compile
# expect: build succeeds; "  en-US -> ja-JP: ready (installed)" or "FAILED (...)" lines appear
```

- [ ] **Step 8.5:** Commit

```bash
git add Rakefile ext/translation_mac/extconf.rb
git commit -m "feat: add prepare_models rake task and bundle-install hook (CI_SKIP gated)"
```

---

## Task 9: example.rb + README + CLAUDE.md

**Files:**
- Create: `example.rb`
- Modify: `README.md`
- Create: `CLAUDE.md`

- [ ] **Step 9.1:** Create `example.rb`

```ruby
# frozen_string_literal: true

# Example caller for rb-translation-mac.
# Run: bundle exec ruby example.rb

$LOAD_PATH.unshift File.expand_path("lib", __dir__)
require "translation_mac"

puts "Supported languages (#{TranslationMac.supported_languages.size}):"
puts TranslationMac.supported_languages.first(10).join(", ") + ", ..."
puts

status = TranslationMac.status(from: "en-US", to: "ja-JP")
puts "Status en-US -> ja-JP: #{status}"

if status == :installed
  result = TranslationMac.translate("Hello, world!", from: "en-US", to: "ja-JP")
  if result.success
    puts "Translation: #{result.text}"
  else
    puts "Translation failed: #{result.error.class}: #{result.error.message}"
  end
else
  puts "Skipping translate (model not installed). Run: bundle exec rake translation_mac:prepare_models"
end
```

- [ ] **Step 9.2:** Replace `README.md` with the rb-vision-ocrmac-style README

```markdown
# rb-translation-mac

Ruby native binding for Apple's Translation framework (`LanguageAvailability` + `TranslationSession`).

## Requirements

- macOS 15.0+ (Translation framework requirement)
- Ruby 3.2+
- Swift 6.3+
- Bundler 2.x
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
# => ["en-US", "ja-JP", "zh-Hans-CN", ...]

TranslationMac.status(from: "en-US", to: "ja-JP")
# => :installed | :supported | :unsupported
```

### Heavy tier (helper subprocess)

```ruby
result = TranslationMac.translate("Hello", from: "en-US", to: "ja-JP")
result.success    # => true
result.text       # => "こんにちは"

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
```

In `test/`, the integration tests for `translate` and `prepare` are gated by `CI_SKIP`. Set `CI_SKIP=1` in CI to skip them.

## Related projects

- [bash0C7/swift_gem](https://github.com/bash0C7/swift_gem) — scaffolding gem for Swift-extension Ruby gems
- [bash0C7/rb-vision-ocrmac](https://github.com/bash0C7/rb-vision-ocrmac) — Vision (OCR) sibling
- [bash0C7/rb-vision-mac](https://github.com/bash0C7/rb-vision-mac) — Vision (faces, etc.) sibling
- [bash0C7/rb-natural-language-mac](https://github.com/bash0C7/rb-natural-language-mac) — NaturalLanguage sibling
- [bash0C7/rb-speech-mac](https://github.com/bash0C7/rb-speech-mac) — Speech sibling (also uses helper subprocess pattern)
- [bash0C7/rb-sound-analysis-mac](https://github.com/bash0C7/rb-sound-analysis-mac) — SoundAnalysis sibling

## License

MIT.
```

- [ ] **Step 9.3:** Create `CLAUDE.md` (mirrors rb-vision-ocrmac/CLAUDE.md structure)

```markdown
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
| `ext/.../TranslationMacHelper/TranslateView.swift` | SwiftUI view with `.translationTask` |
| `ext/.../extconf.rb` | `SwiftGem::Mkmf.create_swift_makefile` for the .bundle, then appends helper build/codesign/install/post_install Make rules |
| `ext/.../Resources/Info.plist` | `CFBundleIdentifier` for stable codesign identity (no TCC strings — Translation framework is not TCC-gated) |
| `Rakefile` | `Rake::ExtensionTask` + `translation_mac:prepare_models` task |

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
```

- [ ] **Step 9.4:** Verify example.rb runs end-to-end

```bash
bundle exec rake compile
bundle exec ruby example.rb
```
Expected: prints supported languages, status, and (if installed) translation.

- [ ] **Step 9.5:** Commit

```bash
git add example.rb README.md CLAUDE.md
git commit -m "docs: add example.rb, full README, and CLAUDE.md"
```

---

## Task 9.5 (REFACTOR): Self-review for stale or duplicated code

After all features are in, scan for cleanup opportunities introduced during build:

- [ ] **Step 9.5.1:** Confirm there are no leftover scaffold files

```bash
find . -name "sample_test.rb" -o -name "examples" -type d
# expect: no output
```

- [ ] **Step 9.5.2:** Run all tests once more

```bash
bundle exec rake clean clobber compile test
```
Expected: all tests pass or omit; no errors.

- [ ] **Step 9.5.3:** If any refactor needed (e.g. duplicated codesign helper logic), fix and commit:

```bash
git commit -m "refactor: <what>"
```

If nothing to refactor, skip.

---

## Task 10: Final integration verify (no commits)

- [ ] **Step 10.1:** Clean rebuild

```bash
rm -rf lib/translation_mac/translation_mac.bundle lib/translation_mac/TranslationMacHelper tmp/
bundle exec rake clean clobber compile
```

- [ ] **Step 10.2:** Full test suite

```bash
bundle exec rake test
```
Verify: All HelperClient unit tests (12) pass. LanguageAvailability tests (3) pass. translate/prepare integration tests pass or omit cleanly.

- [ ] **Step 10.3:** End-to-end

```bash
bundle exec ruby example.rb
```
Verify: prints supported languages, status, and translation (if model installed) without raising.

- [ ] **Step 10.4:** Smoke test direct helper invocation

```bash
./lib/translation_mac/TranslationMacHelper translate en-US ja-JP "Good morning"
echo "exit: $?"
./lib/translation_mac/TranslationMacHelper prepare en-US ja-JP
echo "exit: $?"
```
Verify: Both return non-empty stdout and exit 0 (assuming installed).

- [ ] **Step 10.5:** Verify Gemfile.lock not tracked

```bash
git check-ignore -v Gemfile.lock
# expect: prints .gitignore line
git ls-files | grep -i gemfile
# expect: only "Gemfile"
```

---

## Notes for implementer

- **Locale.Language identifier format:** Apple accepts BCP-47 (`en-US`, `ja-JP`, `zh-Hans-CN`). The Swift API silently normalizes; if you pass `"en"` you may get back `"en-US"` from `maximalIdentifier`. Tests assert `start_with?("en")` to remain robust.
- **Why DispatchSemaphore in TranslationMac.swift but not in HelperApp:** The .bundle is loaded into Ruby's process; we cannot control Ruby's run loop, so we synchronously block on `Task` completion via semaphore. The helper has its own `NSApplication.run()` loop, so SwiftUI's async lifecycle works natively.
- **Why `setActivationPolicy(.accessory)`:** Prevents the Dock icon from appearing during helper execution. The window is invisible (`borderless`, 1×1, never displayed via `orderOut`). Use `makeKeyAndOrderFront(nil)` only if SwiftUI lifecycle requires the window to be in-screen; if `translationTask` doesn't fire, switch to a visible window or experiment with `NSWindow.collectionBehavior`.
- **If `translationTask` doesn't fire (helper hangs at timeout):** Likely the SwiftUI render cycle isn't ticking. Try moving the configuration assignment from `.onAppear` to inside `init()`, or wrap `TranslateView` in `WindowGroup` and use `App` protocol instead of manual `NSApplication`. This is the single biggest implementation risk.
- **First-run language model download:** macOS shows a sheet. The helper window is invisible, so the sheet may attach to the helper's invisible window, never get shown to the user, and hang indefinitely. If this happens during `prepare`, switch the helper to a visible 100×100 window, position it centered, and close it after completion. Document this UX clearly in README if it occurs.

---

## Self-review against spec

| Spec section | Plan task |
|---|---|
| Position | (no impl needed; documented in CLAUDE.md, Task 9.3) |
| Background research | (informational; cited in spec only) |
| Public Ruby API — lightweight tier | Task 3 |
| Public Ruby API — heavy tier | Task 4 (HelperClient) + Task 6 (helper) |
| Result types (H2) | Task 2 |
| Error classes | Task 2 + Task 4 (mapping) |
| Architecture | Tasks 3, 4, 5, 6 (full chain) |
| File layout | Tasks 1, 2, 3, 4, 5, 6, 7, 9 |
| Helper subprocess design — CLI signature | Task 6.1 |
| Helper subprocess design — exit codes | Task 4.6 (mapping) + Task 6.3 (emission) |
| Helper subprocess design — threading | Task 6.2 + 6.3 |
| Helper subprocess design — codesign | Task 5.2 |
| Bundle install integration | Task 8 |
| Default language pairs en-US ↔ ja-JP | Task 8.1 |
| macOS 15.0 | Task 1.1 |
| Test strategy — lightweight | Task 3 |
| Test strategy — heavy CI_SKIP gated | Task 7 |
| Decisions log H2 / pairs / CI_SKIP | Tasks 2, 7, 8 |
| Out of scope items | (intentionally absent from plan) |
| Prohibitions | CLAUDE.md (Task 9.3) |

No gaps detected.
