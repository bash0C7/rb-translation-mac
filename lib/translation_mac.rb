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
