require "json"

module Henni
  class IgnoreList
    FILENAME = ".henni-ignore.json"

    def self.load(root, target)
      path = File.join(root, FILENAME)
      return new([]) unless File.exist?(path)

      entries = JSON.parse(File.read(path), symbolize_names: true)
      raise ArgumentError, "#{FILENAME} must contain an array" unless entries.is_a?(Array)
      entries.each do |entry|
        unless entry.is_a?(Hash) && %i[path id scope_fingerprint reason].all? { |key| entry[key].is_a?(String) && !entry[key].strip.empty? }
          raise ArgumentError, "#{FILENAME} entries require path, id, scope_fingerprint and reason"
        end
      end
      new(entries.select { |entry| entry[:path] == target })
    end

    def initialize(entries)
      @entries = entries.to_h { |entry| [entry[:id], entry] }
      raise ArgumentError, "duplicate mutation ID in #{FILENAME}" unless entries.size == @entries.size
    end

    def apply(mutations)
      stale = @entries.dup
      mutations.each do |mutation|
        entry = @entries[mutation[:id]]
        next unless entry && entry[:scope_fingerprint] == mutation[:scope_fingerprint]

        mutation.merge!(status: "ignored", reason: entry[:reason])
        stale.delete(mutation[:id])
      end
      stale.values
    end
  end
end
