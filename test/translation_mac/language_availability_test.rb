# frozen_string_literal: true

require "test_helper"

class LanguageAvailabilityTest < Test::Unit::TestCase
  test "supported_languages returns array including English and Japanese tags" do
    langs = TranslationMac.supported_languages
    assert_kind_of(Array, langs)
    assert(langs.any? { |l| l.start_with?("en") }, "expected an en-* tag, got: #{langs.inspect}")
    assert(langs.any? { |l| l.start_with?("ja") }, "expected a ja-* tag, got: #{langs.inspect}")
  end

  test "status returns one of installed / supported / unsupported" do
    status = TranslationMac.status(from: "en-US", to: "ja-JP")
    assert_includes([:installed, :supported, :unsupported], status)
  end

  test "status returns :unsupported for nonsense pair" do
    status = TranslationMac.status(from: "xx-XX", to: "yy-YY")
    assert_equal(:unsupported, status)
  end
end
