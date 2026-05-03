# frozen_string_literal: true

# Example caller for rb-translation-mac.
# Run: bundle exec ruby example.rb

$LOAD_PATH.unshift File.expand_path("lib", __dir__)
require "translation_mac"

puts "Supported languages (#{TranslationMac.supported_languages.size}):"
puts TranslationMac.supported_languages.first(10).join(", ") + ", ..."
puts

status = TranslationMac.status(from: "en-US", to: "ja-JP")
puts "Status en-US -> ja-JP: #{status}"

if status == :installed
  result = TranslationMac.translate("Hello, world!", from: "en-US", to: "ja-JP")
  if result.success
    puts "Translation: #{result.text}"
  else
    puts "Translation failed: #{result.error.class}: #{result.error.message}"
  end
else
  puts "Skipping translate (model not installed). Run: bundle exec rake translation_mac:prepare_models"
end
