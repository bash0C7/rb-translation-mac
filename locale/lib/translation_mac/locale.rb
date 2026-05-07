# frozen_string_literal: true

# Locale-aware easy-to-use layer over rb-translation-mac.
#
# Activated by:
#   require "translation_mac/locale"
#   t = TranslationMac::Locale::Translator.new(target_lang: "ja-JP")
#   t.translate("Hello")
#
# Logical sub-gem inside rb-translation-mac, path-loaded via Gemfile.
# Adds LANG → BCP-47 normalization, English/C/POSIX skip logic, per-
# input cache, and silent degrade — the convenience boilerplate that
# every TranslationMac.translate consumer otherwise has to re-implement.
require "translation_mac"

module TranslationMac
  module Locale
  end
end

require "translation_mac/locale/translator"
