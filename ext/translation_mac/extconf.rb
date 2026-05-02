# frozen_string_literal: true

require "swift_gem/mkmf"

SwiftGem::Mkmf.create_swift_makefile(
  "translation_mac/translation_mac",
  package: "TranslationMac",
  source_dir: __dir__
)
