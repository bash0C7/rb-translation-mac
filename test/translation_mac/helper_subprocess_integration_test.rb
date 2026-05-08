# frozen_string_literal: true

require "test_helper"
require "open3"

# Phase B verification: the Helper binary supports `status <from> <to>`
# and `languages` subcommands directly. These tests bypass the Ruby module
# (TranslationMac.status etc.) and call the binary via Open3 to isolate
# Helper-side bugs from Ruby-side wire-up bugs.
class HelperSubprocessIntegrationTest < Test::Unit::TestCase
  def setup
    omit("CI_SKIP set") if ENV["CI_SKIP"]
    @helper = TranslationMac::DEFAULT_HELPER_PATH
    omit("helper binary missing — run `bundle exec rake compile`") unless File.executable?(@helper)
  end

  test "status subcommand returns one of installed / supported / unsupported on exit 0" do
    stdout, _stderr, status = Open3.capture3(@helper, "status", "en-US", "ja-JP")
    assert_equal(0, status.exitstatus)
    assert_includes(%w[installed supported unsupported], stdout.strip)
  end

  test "status subcommand for nonsense pair returns unsupported on exit 0" do
    stdout, _stderr, status = Open3.capture3(@helper, "status", "xx-XX", "yy-YY")
    assert_equal(0, status.exitstatus)
    assert_equal("unsupported", stdout.strip)
  end

  test "languages subcommand returns newline-separated BCP-47 tags including en and ja" do
    stdout, _stderr, status = Open3.capture3(@helper, "languages")
    assert_equal(0, status.exitstatus)
    tags = stdout.split("\n").map(&:strip).reject(&:empty?)
    assert(tags.any? { |t| t.start_with?("en") }, "expected en-* tag, got: #{tags.inspect}")
    assert(tags.any? { |t| t.start_with?("ja") }, "expected ja-* tag, got: #{tags.inspect}")
  end
end
