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
