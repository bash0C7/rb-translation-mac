# frozen_string_literal: true

require "open3"

module TranslationMac
  class HelperClient
    EXIT_CODE_ERRORS = {
      2 => ModelNotInstalledError,
      3 => UnsupportedLanguagePairError,
      4 => TimeoutError,
    }.freeze

    PREPARE_STATUSES = {
      "installed"   => :installed,
      "supported"   => :supported,
      "unsupported" => :unsupported,
    }.freeze

    def initialize(helper_path)
      @helper_path = helper_path
    end

    def translate(text, from:, to:)
      stdout, stderr, status = run("translate", from, to, text)
      if status.exitstatus&.zero?
        TranslationResult.new(text: stdout, success: true, error: nil)
      else
        TranslationResult.new(text: nil, success: false, error: error_for(status, stderr))
      end
    rescue Errno::ENOENT, Errno::EACCES => e
      TranslationResult.new(text: nil, success: false, error: HelperSpawnError.new(e.message))
    end

    def prepare(from:, to:)
      stdout, stderr, status = run("prepare", from, to)
      sym = PREPARE_STATUSES.fetch(stdout.strip, :unknown)
      if status.exitstatus&.zero?
        PrepareResult.new(status: sym, success: true, error: nil)
      else
        PrepareResult.new(status: :unknown, success: false, error: error_for(status, stderr))
      end
    rescue Errno::ENOENT, Errno::EACCES => e
      PrepareResult.new(status: :unknown, success: false, error: HelperSpawnError.new(e.message))
    end

    def status(from:, to:)
      stdout, _stderr, status = run("status", from, to)
      if status.exitstatus&.zero?
        case stdout.strip
        when "installed"   then :installed
        when "supported"   then :supported
        when "unsupported" then :unsupported
        else :unsupported
        end
      else
        :unsupported
      end
    rescue Errno::ENOENT, Errno::EACCES
      :unsupported
    end

    def supported_languages
      stdout, _stderr, status = run("languages")
      return [] unless status.exitstatus&.zero?
      return [] if stdout.strip.empty?
      stdout.split("\n").map(&:strip).reject(&:empty?)
    rescue Errno::ENOENT, Errno::EACCES
      []
    end

    private

    def run(*args)
      Open3.capture3(@helper_path, *args)
    end

    def error_for(status, stderr)
      return HelperCrashError.new(crash_message(stderr, status)) if status.exitstatus.nil?
      klass = EXIT_CODE_ERRORS[status.exitstatus]
      return klass.new(stderr) if klass
      HelperCrashError.new(stderr.empty? ? "exit #{status.exitstatus}" : stderr)
    end

    def crash_message(stderr, status)
      return stderr unless stderr.empty?
      sig = status&.termsig
      sig ? "killed by signal #{sig}" : "killed by signal"
    end
  end
end
