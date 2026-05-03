# frozen_string_literal: true

require "test_helper"

class HelperClientTest < Test::Unit::TestCase
  include FakeHelperSupport

  def build_client(exit_code: 0, stdout: "", stderr: "", path: FAKE_HELPER)
    ENV["FAKE_EXIT"]   = exit_code.to_s
    ENV["FAKE_STDOUT"] = stdout
    ENV["FAKE_STDERR"] = stderr
    TranslationMac::HelperClient.new(path)
  end

  # ----- translate -----

  test "translate exit 0 -> TranslationResult(success: true, text: stdout)" do
    client = build_client(exit_code: 0, stdout: "こんにちは")
    result = client.translate("Hello", from: "en-US", to: "ja-JP")
    assert_kind_of(TranslationMac::TranslationResult, result)
    assert_equal(true, result.success)
    assert_equal("こんにちは", result.text)
    assert_nil(result.error)
  end

  test "translate exit 2 -> ModelNotInstalledError" do
    client = build_client(exit_code: 2)
    result = client.translate("Hello", from: "en-US", to: "ja-JP")
    assert_equal(false, result.success)
    assert_nil(result.text)
    assert_kind_of(TranslationMac::ModelNotInstalledError, result.error)
  end

  test "translate exit 3 -> UnsupportedLanguagePairError" do
    client = build_client(exit_code: 3)
    result = client.translate("Hello", from: "en-US", to: "xx-XX")
    assert_kind_of(TranslationMac::UnsupportedLanguagePairError, result.error)
  end

  test "translate exit 4 -> TimeoutError" do
    client = build_client(exit_code: 4)
    result = client.translate("Hello", from: "en-US", to: "ja-JP")
    assert_kind_of(TranslationMac::TimeoutError, result.error)
  end

  test "translate exit 5 -> HelperCrashError with stderr in message" do
    client = build_client(exit_code: 5, stderr: "internal: foo")
    result = client.translate("Hello", from: "en-US", to: "ja-JP")
    assert_kind_of(TranslationMac::HelperCrashError, result.error)
    assert_match(/internal: foo/, result.error.message)
  end

  test "translate unknown exit -> HelperCrashError" do
    client = build_client(exit_code: 99, stderr: "segfault")
    result = client.translate("Hello", from: "en-US", to: "ja-JP")
    assert_kind_of(TranslationMac::HelperCrashError, result.error)
  end

  test "translate with missing helper binary -> HelperSpawnError" do
    client = TranslationMac::HelperClient.new("/nonexistent/__missing_xyz")
    result = client.translate("Hello", from: "en-US", to: "ja-JP")
    assert_kind_of(TranslationMac::HelperSpawnError, result.error)
    assert_equal(false, result.success)
  end

  test "translate with helper killed by signal -> HelperCrashError" do
    ENV["FAKE_SIGNAL"] = "KILL"
    client = TranslationMac::HelperClient.new(FAKE_HELPER)
    result = client.translate("Hello", from: "en-US", to: "ja-JP")
    assert_kind_of(TranslationMac::HelperCrashError, result.error)
    assert_equal(false, result.success)
  end

  # ----- prepare -----

  test "prepare exit 0 stdout=installed -> PrepareResult(:installed, success: true)" do
    client = build_client(exit_code: 0, stdout: "installed")
    result = client.prepare(from: "en-US", to: "ja-JP")
    assert_kind_of(TranslationMac::PrepareResult, result)
    assert_equal(:installed, result.status)
    assert_equal(true, result.success)
    assert_nil(result.error)
  end

  test "prepare exit 3 -> PrepareResult(:unknown, UnsupportedLanguagePairError)" do
    client = build_client(exit_code: 3)
    result = client.prepare(from: "xx-XX", to: "yy-YY")
    assert_equal(:unknown, result.status)
    assert_equal(false, result.success)
    assert_kind_of(TranslationMac::UnsupportedLanguagePairError, result.error)
  end

  test "prepare with missing helper binary -> HelperSpawnError" do
    client = TranslationMac::HelperClient.new("/nonexistent/__missing_xyz")
    result = client.prepare(from: "en-US", to: "ja-JP")
    assert_equal(false, result.success)
    assert_kind_of(TranslationMac::HelperSpawnError, result.error)
  end

  test "prepare with helper killed by signal -> HelperCrashError" do
    ENV["FAKE_SIGNAL"] = "KILL"
    client = TranslationMac::HelperClient.new(FAKE_HELPER)
    result = client.prepare(from: "en-US", to: "ja-JP")
    assert_kind_of(TranslationMac::HelperCrashError, result.error)
  end
end
