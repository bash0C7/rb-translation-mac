# frozen_string_literal: true

module TranslationMac
  TranslationResult = Data.define(:text, :success, :error)
  PrepareResult     = Data.define(:status, :success, :error)
end
