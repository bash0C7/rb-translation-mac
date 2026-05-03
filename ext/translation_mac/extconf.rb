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
