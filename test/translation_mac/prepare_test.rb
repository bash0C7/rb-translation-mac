# frozen_string_literal: true

require "test_helper"

class PrepareIntegrationTest < Test::Unit::TestCase
  def setup
    omit("CI_SKIP set") if ENV["CI_SKIP"]
  end

  test "prepare for installed pair returns success" do
    status = TranslationMac.status(from: "en-US", to: "ja-JP")
    omit("not installed (got #{status}); skipping to avoid system download dialog") unless status == :installed
    result = TranslationMac.prepare(from: "en-US", to: "ja-JP")
    assert_kind_of(TranslationMac::PrepareResult, result)
    assert_equal(true, result.success, "error: #{result.error&.message}")
    assert_equal(:installed, result.status)
  end

  test "prepare for unsupported pair returns UnsupportedLanguagePairError" do
    result = TranslationMac.prepare(from: "xx-XX", to: "yy-YY")
    assert_equal(false, result.success)
    assert_kind_of(TranslationMac::UnsupportedLanguagePairError, result.error)
  end
end
