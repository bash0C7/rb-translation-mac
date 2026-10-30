# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "fileutils"

HELPER_DIR = "ext/translation_mac"
HELPER_OUTPUT = File.join(HELPER_DIR, ".build/release/TranslationMacHelper")
HELPER_DEST = "lib/translation_mac/TranslationMacHelper"
HELPER_BUNDLE_ID = "com.bash0c7.rb-translation-mac.helper"

desc "Build the Swift package, then sign and install the helper"
task :swift do
  sh "xcrun", "swift", "build", "-c", "release", "--package-path", HELPER_DIR, "--product", "TranslationMacHelper"
  sh "codesign", "-s", "-", "--force", "--identifier", HELPER_BUNDLE_ID, "--options", "runtime", HELPER_OUTPUT
  FileUtils.install(HELPER_OUTPUT, HELPER_DEST, mode: 0o755)
end

task compile: :swift

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

desc "Validate the RBS signatures"
task :rbs do
  sh "rbs", "-I", "sig", "validate"
end

desc "Start an IRB console with translation_mac loaded"
task console: :compile do
  require "irb"
  $LOAD_PATH.unshift File.expand_path("lib", __dir__)
  require "translation_mac"
  ARGV.clear
  IRB.start
end

namespace :translation_mac do
  desc "Download language models (default: en-US <-> ja-JP). Override via TRANSLATION_MAC_PAIRS=en-US:fr-FR,fr-FR:en-US"
  task prepare_models: :compile do
    $LOAD_PATH.unshift File.expand_path("lib", __dir__)
    require "translation_mac"
    ENV.fetch("TRANSLATION_MAC_PAIRS", "en-US:ja-JP,ja-JP:en-US").split(",").each do |pair|
      from, to = pair.split(":")
      result = TranslationMac.prepare(from: from, to: to)
      label = result.success ? "ready (#{result.status})" : "FAILED (#{result.error.class.name})"
      puts "  #{from} -> #{to}: #{label}"
    end
  end
end

task test: %i[rbs compile]
task default: :test
