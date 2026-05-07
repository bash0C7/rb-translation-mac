# frozen_string_literal: true

require_relative "../lib/translation_mac/version"

Gem::Specification.new do |spec|
  spec.name = "translation_mac-locale"
  spec.version = TranslationMac::VERSION
  spec.authors = ["bash0C7"]
  spec.email = ["ksb.4038.nullpointer+github@gmail.com"]

  spec.summary = "Locale-aware easy-to-use layer over rb-translation-mac"
  spec.description = <<~DESC
    Logical sub-gem of rb-translation-mac that adds the conveniences
    every consumer of TranslationMac.translate ends up writing:
    - POSIX LANG (e.g. "ja_JP.UTF-8") → BCP-47 ("ja-JP") normalization
    - Skip-or-translate decision for English / C / POSIX / blank locales
    - Per-input result cache (Mutex-guarded)
    - Result-struct unwrapping with silent degrade to the input string
      on any provider failure (suitable for UI hover / popup contexts)
    Bound to the parent rb-translation-mac via path: dependency, not
    published independently to rubygems.org.
  DESC
  spec.homepage = "https://github.com/bash0C7/rb-translation-mac"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/bash0C7/rb-translation-mac/tree/main/locale"

  spec.files = Dir.chdir(__dir__) do
    Dir.glob(["lib/**/*.rb", "README.md"]).reject { |f| File.directory?(f) }
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "rb-translation-mac"

  spec.add_development_dependency "test-unit", "~> 3.6"
  spec.add_development_dependency "rake", "~> 13.0"
end
