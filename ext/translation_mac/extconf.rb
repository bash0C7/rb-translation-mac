# frozen_string_literal: true

require "swift_gem/mkmf"

BUNDLE_ID = "com.bash0c7.rb-translation-mac.helper"

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

# 1. Let swift_gem build the lightweight tier (.bundle).
#    Scope -emit-clang-header-path to ONLY the TranslationMac library target
#    via --product, otherwise SwiftPM also builds TranslationMacHelper and the
#    same -Xswiftc flag applies to both targets — whichever finishes last
#    overwrites TranslationMac-Swift.h, breaking the C bridge build on the
#    next invocation. The helper is built separately by the appended Make
#    rules below (which intentionally do NOT pass -emit-clang-header-path).
lib_only_builder = lambda do |package, source_dir|
  header_path = File.join(File.expand_path(source_dir), "#{package}-Swift.h")
  ok = system(
    "swift", "build", "-c", "release", "--package-path", source_dir,
    "--product", package,
    "-Xswiftc", "-emit-clang-header-path", "-Xswiftc", header_path
  )
  raise "swift build failed for package #{package.inspect}" unless ok
  File.expand_path(".build/release", source_dir)
end

SwiftGem::Mkmf.create_swift_makefile(
  "translation_mac/translation_mac",
  package: "TranslationMac",
  source_dir: __dir__,
  builder: lib_only_builder
)

# 2. Append helper build/codesign/install rules to the generated Makefile.
#    `helper_output` and `helper_dest` are real file targets (NOT .PHONY) so
#    Make skips swift build + codesign + reinstall when sources are unchanged.
#    Earlier .PHONY-based rules ran swift build on every `make all`, even when
#    that was a no-op (~1s wasted per invocation; rake-compiler triggers it
#    multiple times during `rake test`).
source_dir    = __dir__
gem_root      = File.expand_path("../..", source_dir)
helper_dest   = File.join(gem_root, "lib", "translation_mac", "TranslationMacHelper")
helper_dir    = File.dirname(helper_dest)
helper_output = File.join(source_dir, ".build", "release", "TranslationMacHelper")
helper_sources = [
  File.join(source_dir, "Package.swift"),
  File.join(source_dir, "Resources", "Info.plist"),
  *Dir[File.join(source_dir, "Sources", "TranslationMacHelper", "*.swift")],
]
identity      = detect_codesign_identity

File.open("Makefile", "a") do |f|
  f.puts <<~MAKEFILE

    # ---- helper subprocess (added by extconf.rb) ----
    HELPER_OUTPUT    = #{make_escape(helper_output)}
    HELPER_DEST      = #{make_escape(helper_dest)}
    HELPER_DEST_DIR  = #{make_escape(helper_dir)}
    HELPER_IDENTITY  = #{make_escape(identity)}
    HELPER_BUNDLE_ID = #{BUNDLE_ID}
    HELPER_SOURCES   = #{helper_sources.map { |p| make_escape(p) }.join(" ")}

    $(HELPER_OUTPUT): $(HELPER_SOURCES)
    \tswift build -c release --package-path #{make_escape(source_dir)} --product TranslationMacHelper
    \tcodesign -s '$(HELPER_IDENTITY)' --force --identifier '$(HELPER_BUNDLE_ID)' --options runtime '$(HELPER_OUTPUT)'

    $(HELPER_DEST): $(HELPER_OUTPUT)
    \t@mkdir -p '$(HELPER_DEST_DIR)'
    \tinstall -m 755 '$(HELPER_OUTPUT)' '$(HELPER_DEST)'

    .PHONY: helper helper_install post_install

    helper: $(HELPER_OUTPUT)

    helper_install: $(HELPER_DEST)

    install: helper_install

    # After install, fire prepare_models so first-use is hot.
    # Skipped under CI_SKIP=1 (CI environments cannot answer system download dialog).
    post_install: install
    \t@if [ -z "$$CI_SKIP" ]; then \\
    \t\tcd #{make_escape(gem_root)} && bundle exec rake translation_mac:prepare_models || true; \\
    \tfi

    all: post_install
  MAKEFILE
end

puts "[rb-translation-mac] codesign identity: #{identity}"
puts "[rb-translation-mac] helper install:    #{helper_dest}"
