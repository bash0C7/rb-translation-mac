# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "fileutils"

HELPER_DIR     = File.expand_path("ext/translation_mac", __dir__)
HELPER_OUTPUT  = File.join(HELPER_DIR, ".build/release/TranslationMacHelper")
HELPER_DEST    = File.expand_path("lib/translation_mac/TranslationMacHelper", __dir__)
HELPER_BUNDLE_ID = "com.bash0c7.rb-translation-mac.helper"

def detect_codesign_identity
  override = ENV["TRANSLATION_MAC_CODESIGN_IDENTITY"]
  return override if override && !override.empty?
  output = `security find-identity -v -p codesigning 2>/dev/null`
  candidates = output.scan(/"(Apple Development:[^"]+)"/).flatten
  if candidates.size > 1
    warn "[rb-translation-mac] multiple Apple Development certs found:"
    candidates.each { |c| warn "[rb-translation-mac]   #{c}" }
    warn "[rb-translation-mac] using first; set TRANSLATION_MAC_CODESIGN_IDENTITY to choose"
  end
  candidates.first || "-"
end

HELPER_SOURCES = [
  File.join(HELPER_DIR, "Package.swift"),
  File.join(HELPER_DIR, "Resources", "Info.plist"),
  *Dir[File.join(HELPER_DIR, "Sources", "TranslationMacHelper", "*.swift")],
].freeze
HELPER_HASH_FILE = File.expand_path("lib/translation_mac/.helper_sources_hash", __dir__)

def helper_sources_content_hash
  require "digest"
  d = Digest::SHA256.new
  HELPER_SOURCES.sort.each do |src|
    next unless File.exist?(src)
    d.update(src)
    d.update(File.binread(src))
  end
  d.hexdigest
end

desc "Build and install the TranslationMacHelper subprocess binary"
task :helper_build do
  # Idempotency guard via content-hash file. mtime alone is unreliable
  # because `swift build` and macOS indexing services touch source files
  # without changing content. We hash the actual bytes of every source
  # input + the destination and skip the swift build + codesign + install
  # pipeline when nothing has changed since the last successful install.
  current_hash = helper_sources_content_hash
  installed_hash = File.exist?(HELPER_HASH_FILE) ? File.read(HELPER_HASH_FILE).strip : nil
  needs_build = !File.exist?(HELPER_DEST) || installed_hash != current_hash

  next unless needs_build

  sh "swift", "build", "-c", "release", "--package-path", HELPER_DIR, "--product", "TranslationMacHelper"
  identity = detect_codesign_identity
  sh "codesign", "-s", identity, "--force", "--identifier", HELPER_BUNDLE_ID, "--options", "runtime", HELPER_OUTPUT
  FileUtils.mkdir_p(File.dirname(HELPER_DEST))
  FileUtils.install(HELPER_OUTPUT, HELPER_DEST, mode: 0755)
  File.write(HELPER_HASH_FILE, current_hash)
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

desc "Start an IRB console with translation_mac loaded"
task console: :helper_build do
  require "irb"
  $LOAD_PATH.unshift File.expand_path("lib", __dir__)
  require "translation_mac"
  ARGV.clear
  IRB.start
end

namespace :translation_mac do
  desc "Pre-download language models (default: en-US <-> ja-JP). Override via TRANSLATION_MAC_PAIRS=en-US:fr-FR,fr-FR:en-US"
  task prepare_models: :helper_build do
    if ENV["CI_SKIP"]
      puts "translation_mac:prepare_models — skipped (CI_SKIP set)"
      next
    end

    pairs = ENV.fetch("TRANSLATION_MAC_PAIRS", "en-US:ja-JP,ja-JP:en-US").split(",")
    $LOAD_PATH.unshift File.expand_path("lib", __dir__)
    require "translation_mac"
    pairs.each do |pair|
      from, to = pair.split(":")
      result = TranslationMac.prepare(from: from, to: to)
      label = result.success ? "ready (#{result.status})" : "FAILED (#{result.error&.class&.name})"
      puts "  #{from} -> #{to}: #{label}"
    end
  end
end

task test: :helper_build
task default: :test
