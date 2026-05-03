# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "rake/extensiontask"

Rake::ExtensionTask.new("translation_mac") do |ext|
  ext.lib_dir = "lib/translation_mac"
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
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
  desc "Pre-download language models (default: en-US <-> ja-JP). Override via TRANSLATION_MAC_PAIRS=en-US:fr-FR,fr-FR:en-US"
  task prepare_models: :compile do
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

task test: :compile
task default: :test
