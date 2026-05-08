# Availability API Helper-Subprocess Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `TranslationMac.status` and `TranslationMac.supported_languages` off the in-process C/Swift bridge and onto the existing `TranslationMacHelper` subprocess pattern, then delete the obsolete in-process code path entirely. Eliminates the `LanguageAvailability` semaphore-deadlock hang that bites headless Ruby hosts (`bundle exec rake test`, plain `ruby` scripts, daemon processes).

**Architecture:** All four `TranslationMac` module APIs (`translate`, `prepare`, `status`, `supported_languages`) funnel through `HelperClient`, which spawns `TranslationMacHelper` via `Open3.capture3`. The Helper runs `NSApp.shared.run()` so async `LanguageAvailability` continuations get serviced correctly. The in-process Swift bridge + C extension are removed (sources, gemspec extension config, Rakefile compile step, and the build-artifact `lib/translation_mac/translation_mac.bundle`).

**Tech Stack:** Ruby 4.0.3, test-unit, Open3, Apple Translation framework (macOS 15.0+), Swift 6.3, SwiftPM, SwiftUI `.translationTask` for translate/prepare path, `LanguageAvailability` direct call for status/languages path.

---

## File Structure

**Modified files:**

- `lib/translation_mac/helper_client.rb` — add `#status` and `#supported_languages` methods (Phase A). One responsibility: subprocess invocation + result parsing for all four operations.
- `test/translation_mac/helper_client_test.rb` — add 10 unit tests for the new methods (Phase A).
- `ext/translation_mac/Sources/TranslationMacHelper/main.swift` — add `status` / `languages` argv parsing (Phase B).
- `ext/translation_mac/Sources/TranslationMacHelper/HelperApp.swift` — add `runAvailabilityStatus` / `runSupportedLanguages` direct-Task paths bypassing `TranslateView` (Phase B).
- `lib/translation_mac.rb` — drop `require_relative "translation_mac/translation_mac"` line, add `def self.status` and `def self.supported_languages` (Phase C).
- `rb-translation-mac.gemspec` — drop `spec.extensions` (Phase D).
- `Rakefile` — drop `Rake::ExtensionTask` block; drop `task test: :compile` chain (Phase D).
- `ext/translation_mac/Package.swift` — drop the `TranslationMac` library product/target, keep `TranslationMacHelper` executable (Phase D).

**Created files:**

- `test/translation_mac/helper_subprocess_integration_test.rb` — Phase B RED test that calls the Helper binary directly via `Open3.capture3` to prove the new subcommands work, independent of any Ruby module wire-up.

**Deleted files (Phase D):**

- `ext/translation_mac/translation_mac.c` (C extension)
- `ext/translation_mac/Sources/TranslationMac/TranslationMac.swift` (in-process Swift impl)
- `ext/translation_mac/Sources/TranslationMac/TranslationMacBridge.swift` (`@c` C-callable wrappers)
- `ext/translation_mac/extconf.rb` (gem build hook)

**Untracked artifacts that disappear naturally** (in `.gitignore`, no git op needed):

- `lib/translation_mac/translation_mac.bundle` and its `.dSYM`
- `ext/translation_mac/.build/`
- `ext/translation_mac/Makefile`
- `ext/translation_mac/Sources/TranslationMac/TranslationMac-Swift.h`

---

## Operating directory

All commands assume the working directory is the rb-translation-mac repo root unless explicitly stated:

```
cd /Users/bash/dev/src/github.com/bash0C7/rb-translation-mac
```

Ruby version is pinned to 4.0.3 via the `.ruby-version` file already committed. `bundle exec` should pick it up automatically through rbenv.

---

## Task 1: HelperClient#status — RED

**Files:**
- Modify: `test/translation_mac/helper_client_test.rb` (append before the closing `end`)

**Goal:** Six failing tests for `HelperClient#status` covering happy path, unknown stdout, helper crash, missing binary, killed-by-signal, and stderr presence.

- [ ] **Step 1: Append the failing tests**

Open `test/translation_mac/helper_client_test.rb`. Find the closing `end` of the `HelperClientTest` class (around line 106). Insert the following tests immediately before that closing `end`, after the last existing `prepare with helper killed by signal` test:

```ruby
  # ----- status -----

  test "status exit 0 stdout=installed -> :installed" do
    client = build_client(exit_code: 0, stdout: "installed")
    assert_equal(:installed, client.status(from: "en-US", to: "ja-JP"))
  end

  test "status exit 0 stdout=supported -> :supported" do
    client = build_client(exit_code: 0, stdout: "supported")
    assert_equal(:supported, client.status(from: "en-US", to: "ja-JP"))
  end

  test "status exit 0 stdout=unsupported -> :unsupported" do
    client = build_client(exit_code: 0, stdout: "unsupported")
    assert_equal(:unsupported, client.status(from: "xx-XX", to: "yy-YY"))
  end

  test "status exit 0 unknown stdout -> :unsupported (silent degrade)" do
    client = build_client(exit_code: 0, stdout: "wat")
    assert_equal(:unsupported, client.status(from: "en-US", to: "ja-JP"))
  end

  test "status helper crash exit 5 -> :unsupported (silent degrade)" do
    client = build_client(exit_code: 5, stderr: "boom")
    assert_equal(:unsupported, client.status(from: "en-US", to: "ja-JP"))
  end

  test "status missing helper binary -> :unsupported (silent degrade)" do
    client = TranslationMac::HelperClient.new("/nonexistent/__missing_xyz")
    assert_equal(:unsupported, client.status(from: "en-US", to: "ja-JP"))
  end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rake test TEST=test/translation_mac/helper_client_test.rb 2>&1 | tail -30
```

Expected: each new `status …` test fails with `NoMethodError: undefined method 'status' for an instance of TranslationMac::HelperClient`. Existing `translate` / `prepare` tests still PASS. Exit code non-zero.

- [ ] **Step 3: Commit RED**

```bash
git add test/translation_mac/helper_client_test.rb
git commit -m "test: failing spec for HelperClient#status with FakeHelperSupport"
```

---

## Task 2: HelperClient#status — GREEN

**Files:**
- Modify: `lib/translation_mac/helper_client.rb`

**Goal:** Minimum implementation of `#status` that turns Task 1 tests GREEN. Silent-degrade on every failure mode.

- [ ] **Step 1: Add the method**

Open `lib/translation_mac/helper_client.rb`. After the `prepare` method definition (which ends near line 44) but before the `private` keyword (around line 46), insert:

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
```

- [ ] **Step 2: Run tests to verify they pass**

```bash
bundle exec rake test TEST=test/translation_mac/helper_client_test.rb 2>&1 | tail -10
```

Expected: all `status …` tests PASS. Existing `translate` / `prepare` tests still PASS. Exit code 0.

- [ ] **Step 3: Commit GREEN**

```bash
git add lib/translation_mac/helper_client.rb
git commit -m "feat: HelperClient#status delegates to helper subprocess"
```

---

## Task 3: HelperClient#supported_languages — RED

**Files:**
- Modify: `test/translation_mac/helper_client_test.rb` (append after the `status` block from Task 1)

**Goal:** Four failing tests for `#supported_languages` covering happy path, empty stdout, crash, and missing binary.

- [ ] **Step 1: Append the failing tests**

In `test/translation_mac/helper_client_test.rb`, after the last `status …` test added in Task 1, insert:

```ruby
  # ----- supported_languages -----

  test "supported_languages exit 0 with newline-separated tags -> Array" do
    client = build_client(exit_code: 0, stdout: "en-US\nja-JP\nfr-FR")
    assert_equal(["en-US", "ja-JP", "fr-FR"], client.supported_languages)
  end

  test "supported_languages exit 0 empty stdout -> []" do
    client = build_client(exit_code: 0, stdout: "")
    assert_equal([], client.supported_languages)
  end

  test "supported_languages helper crash exit 5 -> [] (silent degrade)" do
    client = build_client(exit_code: 5, stderr: "boom")
    assert_equal([], client.supported_languages)
  end

  test "supported_languages missing helper binary -> [] (silent degrade)" do
    client = TranslationMac::HelperClient.new("/nonexistent/__missing_xyz")
    assert_equal([], client.supported_languages)
  end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rake test TEST=test/translation_mac/helper_client_test.rb 2>&1 | tail -20
```

Expected: each `supported_languages …` test fails with `NoMethodError: undefined method 'supported_languages' for an instance of TranslationMac::HelperClient`. All earlier (translate / prepare / status) tests still PASS.

- [ ] **Step 3: Commit RED**

```bash
git add test/translation_mac/helper_client_test.rb
git commit -m "test: failing spec for HelperClient#supported_languages"
```

---

## Task 4: HelperClient#supported_languages — GREEN

**Files:**
- Modify: `lib/translation_mac/helper_client.rb`

**Goal:** Minimum implementation that turns Task 3 tests GREEN.

- [ ] **Step 1: Add the method**

Open `lib/translation_mac/helper_client.rb`. After the `status` method added in Task 2 but before the `private` keyword, insert:

```ruby
    def supported_languages
      stdout, _stderr, status = run("languages")
      return [] unless status.exitstatus&.zero?
      return [] if stdout.strip.empty?
      stdout.split("\n").map(&:strip).reject(&:empty?)
    rescue Errno::ENOENT, Errno::EACCES
      []
    end
```

- [ ] **Step 2: Run tests to verify they pass**

```bash
bundle exec rake test TEST=test/translation_mac/helper_client_test.rb 2>&1 | tail -10
```

Expected: all `supported_languages …` tests PASS. Existing tests still PASS. Exit code 0.

- [ ] **Step 3: Commit GREEN**

```bash
git add lib/translation_mac/helper_client.rb
git commit -m "feat: HelperClient#supported_languages delegates to helper subprocess"
```

---

## Task 5: Helper subprocess integration test — RED

**Files:**
- Create: `test/translation_mac/helper_subprocess_integration_test.rb`

**Goal:** Two failing tests that invoke the Helper binary directly via `Open3.capture3` with the new `status` / `languages` subcommands. These prove the Swift Helper itself supports the new args, independent of any Ruby module wire-up.

- [ ] **Step 1: Create the test file**

Write the following content to `test/translation_mac/helper_subprocess_integration_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require "open3"

# Phase B verification: the Helper binary supports `status <from> <to>`
# and `languages` subcommands directly. These tests bypass the Ruby module
# (TranslationMac.status etc.) and call the binary via Open3 to isolate
# Helper-side bugs from Ruby-side wire-up bugs.
class HelperSubprocessIntegrationTest < Test::Unit::TestCase
  def setup
    omit("CI_SKIP set") if ENV["CI_SKIP"]
    @helper = TranslationMac::DEFAULT_HELPER_PATH
    omit("helper binary missing — run `bundle exec rake compile`") unless File.executable?(@helper)
  end

  test "status subcommand returns one of installed / supported / unsupported on exit 0" do
    stdout, _stderr, status = Open3.capture3(@helper, "status", "en-US", "ja-JP")
    assert_equal(0, status.exitstatus)
    assert_includes(%w[installed supported unsupported], stdout.strip)
  end

  test "status subcommand for nonsense pair returns unsupported on exit 0" do
    stdout, _stderr, status = Open3.capture3(@helper, "status", "xx-XX", "yy-YY")
    assert_equal(0, status.exitstatus)
    assert_equal("unsupported", stdout.strip)
  end

  test "languages subcommand returns newline-separated BCP-47 tags including en and ja" do
    stdout, _stderr, status = Open3.capture3(@helper, "languages")
    assert_equal(0, status.exitstatus)
    tags = stdout.split("\n").map(&:strip).reject(&:empty?)
    assert(tags.any? { |t| t.start_with?("en") }, "expected en-* tag, got: #{tags.inspect}")
    assert(tags.any? { |t| t.start_with?("ja") }, "expected ja-* tag, got: #{tags.inspect}")
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bundle exec rake test TEST=test/translation_mac/helper_subprocess_integration_test.rb 2>&1 | tail -30
```

Expected: each test fails. Either the Helper exits with status 5 + stderr `usage: …` (because `main.swift` falls through to `usage()` on unknown subcommands) or the assertion on the symbol value fails. Exit code non-zero.

- [ ] **Step 3: Commit RED**

```bash
git add test/translation_mac/helper_subprocess_integration_test.rb
git commit -m "test: failing spec for direct Helper status / languages subcommand invocation"
```

---

## Task 6: Helper subprocess subcommand support — GREEN

**Files:**
- Modify: `ext/translation_mac/Sources/TranslationMacHelper/main.swift`
- Modify: `ext/translation_mac/Sources/TranslationMacHelper/HelperApp.swift`

**Goal:** Add `status` / `languages` argv parsing and direct-Task paths in `HelperApp` that bypass `TranslateView` (no `TranslationSession.Configuration` needed for pure availability queries). Rebuild the Swift Helper. Make Task 5 GREEN.

- [ ] **Step 1: Extend `Operation` and add new argv branches**

Open `ext/translation_mac/Sources/TranslationMacHelper/main.swift`. The `Operation` enum is currently defined elsewhere; check `HelperApp.swift` for it. The argv switch in `main.swift` looks like:

```swift
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

Replace the `switch command { … }` block with:

```swift
switch command {
case "translate":
    guard args.count >= 5 else { usage() }
    app.run(operation: .translate(from: args[2], to: args[3], text: args[4]))
case "prepare":
    guard args.count >= 4 else { usage() }
    app.run(operation: .prepare(from: args[2], to: args[3]))
case "status":
    guard args.count >= 4 else { usage() }
    app.run(operation: .status(from: args[2], to: args[3]))
case "languages":
    app.run(operation: .supportedLanguages)
default:
    usage()
}
```

Also extend the `usage()` function's stderr output. Replace:

```swift
func usage() -> Never {
    FileHandle.standardError.write(Data("usage:\n".utf8))
    FileHandle.standardError.write(Data("  TranslationMacHelper translate <from> <to> <text>\n".utf8))
    FileHandle.standardError.write(Data("  TranslationMacHelper prepare <from> <to>\n".utf8))
    exit(5)
}
```

with:

```swift
func usage() -> Never {
    FileHandle.standardError.write(Data("usage:\n".utf8))
    FileHandle.standardError.write(Data("  TranslationMacHelper translate <from> <to> <text>\n".utf8))
    FileHandle.standardError.write(Data("  TranslationMacHelper prepare <from> <to>\n".utf8))
    FileHandle.standardError.write(Data("  TranslationMacHelper status <from> <to>\n".utf8))
    FileHandle.standardError.write(Data("  TranslationMacHelper languages\n".utf8))
    exit(5)
}
```

- [ ] **Step 2: Extend the `Operation` enum and `HelperApp.run`**

Open `ext/translation_mac/Sources/TranslationMacHelper/HelperApp.swift`. Replace the `Operation` enum at the top of the file:

```swift
enum Operation {
    case translate(from: String, to: String, text: String)
    case prepare(from: String, to: String)
}
```

with:

```swift
enum Operation {
    case translate(from: String, to: String, text: String)
    case prepare(from: String, to: String)
    case status(from: String, to: String)
    case supportedLanguages
}
```

Then replace the entire `final class HelperApp { … }` body with:

```swift
@available(macOS 15.0, *)
final class HelperApp {
    func run(operation: Operation) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        switch operation {
        case .translate, .prepare:
            runUITask(operation: operation)
        case .status(let from, let to):
            runAvailabilityStatus(from: from, to: to)
        case .supportedLanguages:
            runSupportedLanguages()
        }

        // Global timeout: 30 s — applies to all four operations.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            FileHandle.standardError.write(Data("timeout".utf8))
            exit(4)
        }

        app.run()
    }

    // translate / prepare path: hosts SwiftUI .translationTask via TranslateView
    // because TranslationSession requires a SwiftUI environment.
    private func runUITask(operation: Operation) {
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
    }

    // status path: LanguageAvailability is callable directly without a
    // TranslationSession; NSApp's main run loop services the async continuation.
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

    // languages path: same direct-Task pattern.
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
}
```

The new file needs `Translation` import. Check the existing imports at the top of `HelperApp.swift`. The file currently imports `AppKit` and `SwiftUI`. Add `Translation` so `LanguageAvailability` resolves:

```swift
import AppKit
import SwiftUI
import Translation
```

- [ ] **Step 3: Rebuild the Swift Helper**

```bash
bundle exec rake compile 2>&1 | tail -20
```

Expected: `swift build` succeeds, `codesign` succeeds, `install` copies the new binary to `lib/translation_mac/TranslationMacHelper`. No compile errors. Exit code 0.

- [ ] **Step 4: Run the Phase B integration tests to verify GREEN**

```bash
bundle exec rake test TEST=test/translation_mac/helper_subprocess_integration_test.rb 2>&1 | tail -10
```

Expected: all 3 tests PASS. The status subcommand for `en-US -> ja-JP` returns `installed` (or `supported` if model not yet downloaded). The languages subcommand returns a list including `en-*` and `ja-*` tags. Exit code 0.

- [ ] **Step 5: Run the existing helper_client_test.rb to confirm no regression**

```bash
bundle exec rake test TEST=test/translation_mac/helper_client_test.rb 2>&1 | tail -10
```

Expected: all (translate + prepare + status + supported_languages) tests PASS.

- [ ] **Step 6: Commit GREEN**

```bash
git add ext/translation_mac/Sources/TranslationMacHelper/main.swift ext/translation_mac/Sources/TranslationMacHelper/HelperApp.swift
git commit -m "feat: Helper supports status / languages subcommands via direct LanguageAvailability path"
```

Note: the rebuilt Helper binary at `lib/translation_mac/TranslationMacHelper` is gitignored (`lib/**/*Helper`) so it does not enter this commit.

---

## Task 7: Route TranslationMac module through HelperClient — GREEN (RED-omit verified)

**Files:**
- Modify: `lib/translation_mac.rb`

**Goal:** Remove `require_relative "translation_mac/translation_mac"` (the C extension load) and replace the C-defined `TranslationMac.status` / `TranslationMac.supported_languages` with Ruby singleton methods that delegate to `HelperClient`. The existing integration tests (`language_availability_test.rb`, `translate_test.rb`, `prepare_test.rb`) cover this — they currently rely on the C-defined methods and will go RED on intermediate state, then GREEN once the Ruby methods are added. Per CLAUDE.md "既存テスト網羅 → RED 省略可、 ただし RED になる変更であることを verify".

- [ ] **Step 1: Verify the existing integration tests would go RED on C-ext removal**

Temporarily comment out the C-ext require line so we can confirm the existing tests would fail in the intermediate state. Open `lib/translation_mac.rb` line 6:

```ruby
require_relative "translation_mac/translation_mac"
```

Change to:

```ruby
# require_relative "translation_mac/translation_mac"
```

Run the existing integration tests:

```bash
bundle exec rake test TEST=test/translation_mac/language_availability_test.rb 2>&1 | tail -20
```

Expected: tests fail with `NoMethodError: undefined method 'status' for module TranslationMac` (or `'supported_languages'`). This confirms the existing tests cover the migration. **Do not commit this intermediate state.**

- [ ] **Step 2: Apply the full GREEN change**

Replace the entire contents of `lib/translation_mac.rb` with:

```ruby
# frozen_string_literal: true

require_relative "translation_mac/version"
require_relative "translation_mac/errors"
require_relative "translation_mac/result"
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

    def status(from:, to:)
      HelperClient.new(helper_path).status(from: from, to: to)
    end

    def supported_languages
      HelperClient.new(helper_path).supported_languages
    end
  end
end
```

The notable changes from the prior file:

1. The `require_relative "translation_mac/translation_mac"` line is gone (C extension no longer loaded).
2. New `def status` and `def supported_languages` singleton methods routing through `HelperClient`.

- [ ] **Step 3: Run the full test suite to confirm everything is GREEN**

```bash
bundle exec rake test 2>&1 | tail -30
```

Expected: all suites PASS, including:

- `helper_client_test.rb` — translate, prepare, status, supported_languages unit tests
- `language_availability_test.rb` — 3 integration tests, no longer hanging
- `translate_test.rb` — 1 integration test, setup `.status` no longer hangs
- `prepare_test.rb` — 2 integration tests, setup `.status` no longer hangs
- `helper_subprocess_integration_test.rb` — 3 direct Helper tests
- Any other test files in `test/translation_mac/`

The full `bundle exec rake test` should complete in well under 30 seconds. **This is the canonical fix-validation moment** — the headless rake test that previously hung 4+ minutes now runs cleanly.

- [ ] **Step 4: Commit GREEN**

```bash
git add lib/translation_mac.rb
git commit -m "refactor: route TranslationMac.{status,supported_languages} through HelperClient"
```

---

## Task 8: Delete obsolete C extension and Swift in-process bridge (chore)

**Files:**
- Delete: `ext/translation_mac/translation_mac.c`
- Delete: `ext/translation_mac/Sources/TranslationMac/TranslationMac.swift`
- Delete: `ext/translation_mac/Sources/TranslationMac/TranslationMacBridge.swift`
- Delete: `ext/translation_mac/extconf.rb`
- Modify: `ext/translation_mac/Package.swift` (drop the `TranslationMac` library product/target, keep `TranslationMacHelper`)
- Modify: `rb-translation-mac.gemspec` (drop `spec.extensions`)
- Modify: `Rakefile` (drop `Rake::ExtensionTask` block + `task test: :compile` chain — the test task no longer depends on a compile step)

**Goal:** Remove all dead code. The native bundle was the only artifact still being built; dropping the gem extension config means `gem build` produces a pure-Ruby gem (apart from the prebuilt `TranslationMacHelper` binary, which is installed as part of the helper-install Make target driven by extconf — but with extconf gone we lose that, so see Step 6 below).

- [ ] **Step 1: Delete the four source files**

```bash
rm ext/translation_mac/translation_mac.c
rm ext/translation_mac/Sources/TranslationMac/TranslationMac.swift
rm ext/translation_mac/Sources/TranslationMac/TranslationMacBridge.swift
```

The `ext/translation_mac/Sources/TranslationMac/` directory will now be empty.

```bash
rmdir ext/translation_mac/Sources/TranslationMac
```

```bash
rm ext/translation_mac/extconf.rb
```

- [ ] **Step 2: Update `Package.swift` — drop the TranslationMac library**

Replace `ext/translation_mac/Package.swift` with the executable-only manifest:

```swift
// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "TranslationMac",
    platforms: [.macOS(.v15)],
    products: [
        .executable(
            name: "TranslationMacHelper",
            targets: ["TranslationMacHelper"]
        ),
    ],
    targets: [
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

- [ ] **Step 3: Update `rb-translation-mac.gemspec` — drop `spec.extensions` and the `swift_gem` runtime dependency**

Open `rb-translation-mac.gemspec`. Find these two lines (around lines 30 and 32):

```ruby
  spec.extensions = ["ext/translation_mac/extconf.rb"]

  spec.add_dependency "swift_gem"
```

Delete both. `swift_gem` was only used by `extconf.rb` (`require "swift_gem/mkmf"` + `SwiftGem::Mkmf.create_swift_makefile`); with extconf gone, the dependency is unused. The trailing portion of the gemspec should now read:

```ruby
  spec.require_paths = ["lib"]
end
```

- [ ] **Step 4: Update `Rakefile` — drop the ExtensionTask + test:compile chain**

Open `Rakefile`. Find this block at the top:

```ruby
require "bundler/gem_tasks"
require "rake/testtask"
require "rake/extensiontask"

Rake::ExtensionTask.new("translation_mac") do |ext|
  ext.lib_dir = "lib/translation_mac"
end
```

Replace with:

```ruby
require "bundler/gem_tasks"
require "rake/testtask"
```

(`Rake::ExtensionTask` is no longer needed; `require "rake/extensiontask"` and the `Rake::ExtensionTask.new` block both go away.)

Find the bottom of the Rakefile:

```ruby
task test: :compile
task default: :test
```

Replace with:

```ruby
task default: :test
```

(`task test: :compile` is dropped because there's no longer a `:compile` task to depend on. `task default: :test` stays.)

Also find this line in the `task console:` block:

```ruby
task console: :compile do
```

Change to:

```ruby
task console: [] do
```

And the same for `task prepare_models: :compile do` inside the `namespace :translation_mac do` block:

```ruby
  task prepare_models: :compile do
```

Change to:

```ruby
  task prepare_models: [] do
```

These two tasks no longer have a compile step to depend on, but the rest of their bodies still need to do their work. We need a way to ensure the Helper binary is up-to-date when `console` or `prepare_models` runs. See Step 5.

- [ ] **Step 5: Replace the `:compile` dependency with a `:helper_build` rake task**

The Helper binary previously got built by extconf.rb's appended Make rules. With extconf gone, we need a Rake task that does the same `swift build` + `codesign` + install dance.

Add a new top-level rake task to `Rakefile`. After the `require` lines and before any `task` declarations, insert:

```ruby
HELPER_DIR     = File.expand_path("ext/translation_mac", __dir__)
HELPER_OUTPUT  = File.join(HELPER_DIR, ".build/release/TranslationMacHelper")
HELPER_DEST    = File.expand_path("lib/translation_mac/TranslationMacHelper", __dir__)
HELPER_BUNDLE_ID = "com.bash0c7.rb-translation-mac.helper"

def detect_codesign_identity
  override = ENV["TRANSLATION_MAC_CODESIGN_IDENTITY"]
  return override if override && !override.empty?
  output = `security find-identity -v -p codesigning 2>/dev/null`
  candidates = output.scan(/"(Apple Development:[^"]+)"/).flatten
  candidates.first || "-"
end

desc "Build and install the TranslationMacHelper subprocess binary"
task :helper_build do
  identity = detect_codesign_identity
  sh "swift", "build", "-c", "release", "--package-path", HELPER_DIR, "--product", "TranslationMacHelper"
  sh "codesign", "-s", identity, "--force", "--identifier", HELPER_BUNDLE_ID, "--options", "runtime", HELPER_OUTPUT
  FileUtils.mkdir_p(File.dirname(HELPER_DEST))
  FileUtils.install(HELPER_OUTPUT, HELPER_DEST, mode: 0755)
end
```

Now wire `:test`, `:console`, and `:prepare_models` to depend on `:helper_build`. Update:

```ruby
task default: :test
```

to:

```ruby
task test: :helper_build
task default: :test
```

Update `task console: [] do` to:

```ruby
task console: :helper_build do
```

Update `task prepare_models: [] do` (inside the namespace) to:

```ruby
task prepare_models: :helper_build do
```

This preserves the previous semantic: running `bundle exec rake test` (or `:console`, or `:prepare_models`) ensures the Helper binary is built and installed first.

`require "fileutils"` may be needed at the top of the Rakefile if it's not already loaded transitively. Add it after `require "rake/testtask"`:

```ruby
require "bundler/gem_tasks"
require "rake/testtask"
require "fileutils"
```

- [ ] **Step 6: Run the full test suite to confirm cleanup did not break anything**

```bash
bundle exec rake test 2>&1 | tail -30
```

Expected: `:helper_build` runs first (swift build + codesign + install), then the test suite runs and all PASS. Exit code 0. Total wall time under 30 seconds (Helper rebuild is incremental — no-op when sources unchanged).

- [ ] **Step 7: Confirm the gem builds cleanly without an extension**

```bash
gem build rb-translation-mac.gemspec 2>&1 | tail -10
```

Expected: `gem build` succeeds and produces a `.gem` file. No `compiling extension` step. The output gem should have `extensions: []` (verify with `gem spec rb-translation-mac-*.gem extensions`).

```bash
gem spec rb-translation-mac-*.gem extensions
# Expected output:
# --- []
```

Clean up the test-built gem:

```bash
rm rb-translation-mac-*.gem
```

- [ ] **Step 8: Confirm no orphan native artifacts remain in `lib/`**

```bash
ls lib/translation_mac/
```

Expected: `errors.rb`, `helper_client.rb`, `result.rb`, `version.rb`, `TranslationMacHelper` (the codesigned subprocess binary). No `translation_mac.bundle`. (If a stale `.bundle` is sitting around from an earlier build, delete it: `rm -f lib/translation_mac/translation_mac.bundle lib/translation_mac/translation_mac.bundle.dSYM`. These are gitignored so no git op is needed.)

- [ ] **Step 9: Commit cleanup**

```bash
git add -A
git status
```

Verify the staged changes show:

- Deleted: `ext/translation_mac/translation_mac.c`
- Deleted: `ext/translation_mac/Sources/TranslationMac/TranslationMac.swift`
- Deleted: `ext/translation_mac/Sources/TranslationMac/TranslationMacBridge.swift`
- Deleted: `ext/translation_mac/extconf.rb`
- Modified: `ext/translation_mac/Package.swift`
- Modified: `rb-translation-mac.gemspec`
- Modified: `Rakefile`

If anything else is staged (`.bundle` files, `.dSYM/` directories, `Makefile`, etc.), unstage them — they should be gitignored already.

```bash
git commit -m "chore: remove obsolete C extension and Swift in-process bridge"
```

---

## Final verification

After all 8 tasks are committed:

- [ ] **Smoke: full headless rake test under detached screen (the original failure scenario)**

```bash
mkdir -p tmp/longrun
screen -dmS final-verify bash -c '
  cd /Users/bash/dev/src/github.com/bash0C7/rb-translation-mac
  bundle exec rake test > tmp/longrun/final-verify.log 2>&1
  echo "DONE: exit=$?" >> tmp/longrun/final-verify.log
'
```

Wait for the `DONE:` sentinel, then inspect:

```bash
until grep -q "^DONE:" tmp/longrun/final-verify.log; do sleep 5; done
tail -20 tmp/longrun/final-verify.log
```

Expected: `DONE: exit=0`, all tests pass, total wall time well under 30 s — the original 4+ minute hang is gone.

- [ ] **Smoke: locale sub-gem still passes (regression check)**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/rb-translation-mac/locale
bundle exec rake test 2>&1 | tail -10
```

Expected: 20 tests / 35 assertions / 0 failures.

- [ ] **Smoke: rb-apple-sdk-mac integration still works**

```bash
cd /Users/bash/dev/src/github.com/bash0C7/rb-apple-sdk-mac
bundle exec ruby tmp/longrun/smoke_translate_real.rb 2>&1
```

Expected: existing translation smoke (English → Japanese) still works end-to-end through the `apple_sdk_mac-irb → translation_mac-locale → TranslationMac.translate → HelperClient → Helper subprocess` pipeline.

---

## Commit history at completion

After all 8 tasks are committed, `git log --oneline -8` from the rb-translation-mac repo should show:

```
chore: remove obsolete C extension and Swift in-process bridge
refactor: route TranslationMac.{status,supported_languages} through HelperClient
feat: Helper supports status / languages subcommands via direct LanguageAvailability path
test: failing spec for direct Helper status / languages subcommand invocation
feat: HelperClient#supported_languages delegates to helper subprocess
test: failing spec for HelperClient#supported_languages
feat: HelperClient#status delegates to helper subprocess
test: failing spec for HelperClient#status with FakeHelperSupport
```

Eight commits, four RED/GREEN pairs (Phase A × 2, Phase B × 1, Phase C bridges via existing tests with no separate RED commit), and one cleanup chore. TDD ledger preserved.
