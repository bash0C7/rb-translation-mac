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
