require "digest"
require "json"

module Henni
  class WorkerReport
    def initialize(target, path)
      @target = File.realpath(target)
      @initial_state = target_state
      @path = path
      start_line_coverage if ENV.delete("HENNI_BASELINE_LINES") == "1"
    end

    def write(**result)
      loaded = $LOADED_FEATURES.any? { |file| File.absolute_path?(file) && File.identical?(file, @target) }
      result[:line_hits] = line_hits if @measuring
      digest = Digest::SHA256.file(@target).hexdigest
      File.write(@path, JSON.generate(result.merge(digest: digest, loaded: loaded, target_changed: target_state != @initial_state)))
    end

    private

    # Also catch a rewrite followed by restoration of the original bytes.
    def target_state
      stat = File.stat(@target)
      [stat.dev, stat.ino, stat.ctime]
    end

    def start_line_coverage
      require "coverage"
      return unless Coverage.state == :idle

      Coverage.start(lines: true)
      @measuring = true
    end

    def line_hits
      return unless Coverage.state == :running

      matches = Coverage.peek_result.select do |file, _measurement|
        File.absolute_path?(file) && File.identical?(file, @target)
      end
      return unless matches.size == 1

      measurement = matches.values.first
      measurement[:lines] if measurement.is_a?(Hash)
    end
  end
end
