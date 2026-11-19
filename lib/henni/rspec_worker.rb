require_relative "worker_report"
require_relative "suites"
require "rspec/core"
require "rspec/expectations"

def assertion_failure?(failure)
  case failure
  when RSpec::Expectations::MultipleExpectationsNotMetError, RSpec::Core::MultipleExceptionError
    failure.all_exceptions.all? { |cause| assertion_failure?(cause) }
  when RSpec::Expectations::ExpectationNotMetError
    true
  else
    (defined?(RSpec::Mocks::MockExpectationError) && failure.is_a?(RSpec::Mocks::MockExpectationError)) ||
      (defined?(Minitest::Assertion) && failure.is_a?(Minitest::Assertion) &&
       !failure.is_a?(Minitest::UnexpectedError) && !failure.is_a?(Minitest::Skip))
  end
end

def aggregated_failure_leaves(failure)
  case failure
  when RSpec::Expectations::MultipleExpectationsNotMetError, RSpec::Core::MultipleExceptionError
    failure.all_exceptions.flat_map { |cause| aggregated_failure_leaves(cause) }
  else
    [failure]
  end
end

target, output, pattern = ARGV.shift(3)
report = Henni::WorkerReport.new(target, output)
args = ["--seed", "12345", "--no-fail-fast"]
# Match the RSpec executable's configured default_path and autorun behavior.
$PROGRAM_NAME = "rspec"
RSpec::Core::Runner.disable_autorun!
if pattern
  files = Henni::Suites.files(pattern)
  abort "no RSpec files match #{pattern}" if files.empty?
  args.concat(files.map { |file| File.expand_path(file) })
end
# Capture the declaration before RSpec generates descriptions for unnamed examples
# from the matcher that executed, which may legitimately change under mutation.
RSpec.configuration.define_derived_metadata do |metadata|
  metadata[:henni_declared_description] = metadata[:full_description].dup if metadata.key?(:execution_result)
end
exit_code = RSpec::Core::Runner.run(args, $stderr, $stderr)
config = RSpec.configuration
examples = config.reporter.examples.map do |example|
  failure = example.exception
  entry = { id: example.id, status: example.execution_result.status, assertion: failure && assertion_failure?(failure),
            exception: failure&.class&.name }
  if failure
    leaves = aggregated_failure_leaves(failure)
    if leaves != [failure]
      entry[:causes] = leaves.map { |cause| { assertion: assertion_failure?(cause), exception: cause.class.name } }
    end
  end
  entry
end
definitions = config.reporter.examples.map do |example|
  [example.id, example.location, example.metadata.fetch(:henni_declared_description)]
end
report.write(exit_code: exit_code, dry_run: config.dry_run, suite_error: !!RSpec.world.non_example_failure,
             expected_ids: RSpec.world.all_examples.map(&:id), examples: examples,
             example_set_digest: Digest::SHA256.hexdigest(JSON.generate(definitions.sort)))
exit exit_code
