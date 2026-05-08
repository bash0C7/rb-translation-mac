# frozen_string_literal: true
require "translation_mac"

module TranslationMac
  module Locale
    # Wraps a translation provider (designed for
    # `TranslationMac.translate(text, from:, to:)` Result API) with the
    # LANG-aware conveniences every consumer ends up writing:
    # - POSIX LANG → BCP-47 normalization (ja_JP.UTF-8 → ja-JP)
    # - Skip English / C / POSIX / blank locales
    # - Per-input result cache (Mutex-guarded)
    # - Silent degrade to original text on any provider failure
    #   so callers in popup / hover contexts never crash
    class Translator
      DEFAULT_SOURCE_LANG = "en-US"

      # POSIX LANG (e.g. "ja_JP.UTF-8") → BCP-47 ("ja-JP"). Returns nil
      # for English locales (no translation needed) and for C / POSIX /
      # blank values, so callers can branch on truthiness alone.
      def self.detect_target_lang(env_lang)
        return nil if env_lang.nil?
        s = env_lang.to_s
        return nil if s.empty?
        return nil if %w[C POSIX].include?(s.upcase)
        base = s.split(".").first.to_s
        bcp47 = base.tr("_", "-")
        return nil if bcp47.empty?
        return nil if english?(bcp47)
        bcp47
      end

      # Resolve target lang from a priority list of env values. The first
      # value that maps to a non-nil BCP-47 tag (i.e. is not nil / blank /
      # English / C / POSIX) wins. Designed for callers that want to
      # layer their own env var (`APPLE_SDK_DOC_LANG`, `MYTOOL_LANG`, ...)
      # on top of POSIX `LANG`. Pass values in priority order.
      def self.detect_target_lang_priority(*env_values)
        env_values.each do |v|
          target = detect_target_lang(v)
          return target if target
        end
        nil
      end

      # Default translate_proc adapter for the parent gem's API. Useful
      # when the caller has no special needs and just wants
      # `Translator.new(target_lang: ...)` to work.
      def self.default_translate_proc
        ->(text, from:, to:) { ::TranslationMac.translate(text, from: from, to: to) }
      end

      def self.english?(bcp47)
        return false if bcp47.nil? || bcp47.empty?
        head = bcp47.downcase
        head == "en" || head.start_with?("en-")
      end

      def initialize(target_lang:, translate_proc: self.class.default_translate_proc, source_lang: DEFAULT_SOURCE_LANG)
        @target_lang = target_lang
        @source_lang = source_lang
        @translate_proc = translate_proc
        @cache = {}
        @mutex = Mutex.new
      end

      def active?
        !@target_lang.nil? && !@target_lang.empty?
      end

      def translate(text)
        return text if text.nil? || text.empty?
        return text unless active?
        cached = @mutex.synchronize { @cache[text] }
        return cached if cached
        translated = invoke_provider(text) || text
        @mutex.synchronize { @cache[text] = translated }
        translated
      end

      private

      def invoke_provider(text)
        result =
          begin
            @translate_proc.call(text, from: @source_lang, to: @target_lang)
          rescue => e
            warn "[translation_mac-locale] #{e.class}: #{e.message}" if ENV["TRANSLATION_LOCALE_DEBUG"]
            return nil
          end
        extract_text(result)
      end

      def extract_text(result)
        return result if result.is_a?(String) && !result.empty?
        return nil unless result.respond_to?(:success)
        return nil unless result.success
        return nil unless result.respond_to?(:text)
        result.text
      end
    end
  end
end
