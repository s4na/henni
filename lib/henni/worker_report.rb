require "digest"
require "json"

module Henni
  class WorkerReport
    def initialize(target, path)
      @target = File.realpath(target)
      @digest = Digest::SHA256.file(@target).hexdigest
      @path = path
      start_line_coverage if ENV.delete("HENNI_BASELINE_LINES") == "1"
    end

    def write(**result)
      loaded = $LOADED_FEATURES.any? { |file| File.absolute_path?(file) && File.identical?(file, @target) }
      result[:line_hits] = line_hits if @measuring
      File.write(@path, JSON.generate(result.merge(digest: @digest, loaded: loaded)))
    end

    private

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
