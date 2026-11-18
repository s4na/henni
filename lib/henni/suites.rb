module Henni
  module Suites
    DEFAULT_TESTS = "test/**/{*_test,test_*}.rb"

    def self.files(pattern, root = Dir.pwd)
      paths = Dir.glob(pattern, base: root).uniq.sort
      paths.select do |path|
        absolute = File.expand_path(path, root)
        raise ArgumentError, "test glob must stay inside the project: #{pattern}" unless absolute.start_with?(root + "/")
        File.file?(absolute)
      end
    end

    def self.test_files(pattern, root = Dir.pwd)
      paths = files(pattern, root)
      paths.reject! { |path| File.basename(path) == "test_helper.rb" } if pattern == DEFAULT_TESTS
      paths
    end

    def self.discover(root, runner, spec_pattern, test_pattern)
      candidates = { "rspec" => spec_pattern, "minitest" => test_pattern || DEFAULT_TESTS }
      return candidates if runner == "both"
      return candidates.slice(runner) unless runner == "auto"

      specs = spec_pattern || File.directory?(File.join(root, "spec")) || File.file?(File.join(root, ".rspec"))
      tests = test_pattern || !test_files(DEFAULT_TESTS, root).empty?
      candidates.select { |name, _| name == "rspec" ? specs : tests }
    end
  end
end
