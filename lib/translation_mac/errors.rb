# frozen_string_literal: true

module TranslationMac
  class Error < StandardError; end
  class ModelNotInstalledError       < Error; end
  class UnsupportedLanguagePairError < Error; end
  class TimeoutError                 < Error; end
  class HelperSpawnError             < Error; end
  class HelperCrashError             < Error; end
end
