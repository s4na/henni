require "digest"
require "json"

module Henni
  class WorkerReport
    def initialize(target, path)
      @target = File.realpath(target)
      @digest = Digest::SHA256.file(@target).hexdigest
      @path = path
    end

    def write(**result)
      loaded = $LOADED_FEATURES.any? { |file| File.absolute_path?(file) && File.identical?(file, @target) }
      File.write(@path, JSON.generate(result.merge(digest: @digest, loaded: loaded)))
    end
  end
end
