# Executed in a fresh Ruby process inside each working copy.
require "digest"
require "json"
require "rspec/core"
require "rspec/expectations"

target, result_path = ARGV.shift(2)
target = File.realpath(target)
digest = Digest::SHA256.file(target).hexdigest
exit_code = RSpec::Core::Runner.run(["--seed", "12345", "--no-fail-fast", "./spec"], $stderr, $stderr)
config = RSpec.configuration
examples = config.reporter.examples
loaded = $LOADED_FEATURES.any? { |file| File.absolute_path?(file) && File.expand_path(file) == target }

result = {
  digest: digest, loaded: loaded, exit_code: exit_code,
  dry_run: config.dry_run, suite_error: !!RSpec.world.non_example_failure,
  expected: RSpec.world.example_count,
  examples: examples.map do |example|
    failure = example.exception
    { id: example.id, status: example.execution_result.status,
      assertion: failure.is_a?(RSpec::Expectations::ExpectationNotMetError),
      exception: failure&.class&.name }
  end
}
File.write(result_path, JSON.generate(result))
exit exit_code
