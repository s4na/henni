require "digest"
require "json"

module Henni
  class WorkerReport
    def initialize(target, path)
      @target = File.realpath(target)
      @initial_state = target_state
      @path = path
    end

    def write(**result)
      loaded = $LOADED_FEATURES.any? { |file| File.absolute_path?(file) && File.identical?(file, @target) }
      digest = Digest::SHA256.file(@target).hexdigest
      File.write(@path, JSON.generate(result.merge(digest: digest, loaded: loaded, target_changed: target_state != @initial_state)))
    end

    private

    # Also catch a rewrite followed by restoration of the original bytes.
    def target_state
      stat = File.stat(@target)
      [stat.dev, stat.ino, stat.ctime]
    end
  end
end
