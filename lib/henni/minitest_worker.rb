require_relative "worker_report"
require_relative "suites"
require "minitest/autorun"

module Henni
  class MinitestReporter < Minitest::AbstractReporter
    def initialize(report)
      super()
      @report = report
      @examples = []
    end

    def start
      @expected_ids = Minitest::Runnable.runnables.flat_map do |suite|
        suite.runnable_methods.map { |method| "#{suite.name}##{method}" }
      end
    end

    def record(result)
      failures = result.failures
      status = if result.skipped? then "pending"
               elsif failures.empty? then "passed"
               else "failed"
               end
      assertion = failures.all? do |failure|
        failure.is_a?(Minitest::Assertion) && !failure.is_a?(Minitest::UnexpectedError) && !failure.is_a?(Minitest::Skip)
      end
      error = failures.find { |failure| failure.is_a?(Minitest::UnexpectedError) }
      exception = error ? error.error : failures.first
      @examples << { id: "#{result.class_name}##{result.name}", status: status,
                     assertion: assertion, exception: exception&.class&.name }
    end

    def report
      @report.write(expected_ids: @expected_ids, examples: @examples,
                    exit_code: @examples.any? { |example| example[:status] == "failed" } ? 1 : 0)
    end
  end
end

target, output, pattern = ARGV.shift(3)
reporter = Henni::MinitestReporter.new(Henni::WorkerReport.new(target, output))
$LOAD_PATH.unshift(File.expand_path("test"))
ARGV.replace(["--seed", "12345"])
Henni::Suites.test_files(pattern).each { |file| require File.expand_path(file) }

Minitest.register_plugin(Module.new do
  define_singleton_method(:minitest_plugin_init) { |_options| Minitest.reporter << reporter }
end)
