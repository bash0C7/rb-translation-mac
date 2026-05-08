# frozen_string_literal: true

require_relative "lib/translation_mac/version"

Gem::Specification.new do |spec|
  spec.name = "rb-translation-mac"
  spec.version = TranslationMac::VERSION
  spec.authors = ["bash0C7"]
  spec.email = ["ksb.4038.nullpointer+github@gmail.com"]

  spec.summary = "Ruby binding for Apple's Translation framework (LanguageAvailability + TranslationSession via SwiftUI helper)"
  spec.description = "rb-translation-mac wraps Apple's Translation framework as a Ruby native extension. The lightweight tier (LanguageAvailability) ships as a .bundle; the heavy tier (TranslationSession) runs in a helper subprocess that hosts SwiftUI to satisfy the framework's UI requirement. Requires macOS 15.0+."
  spec.homepage = "https://github.com/bash0C7/rb-translation-mac"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/bash0C7/rb-translation-mac"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
