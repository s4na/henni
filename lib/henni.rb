require "fileutils"
require "tmpdir"
require "json"
require "optparse"
require "pathname"
require_relative "henni/planner"
require_relative "henni/suites"
require_relative "henni/executor"
require_relative "henni/snapshot"

module Henni
  OMIT = Snapshot::OMIT

  def self.snapshot(root, dest, exclude: [])
    Snapshot.new(exclude).copy(root, dest)
  end

  def self.run(args)
    timeout = 60.0
    runner = "auto"
    spec_pattern = nil
    test_pattern = nil
    excludes = []
    options = OptionParser.new do |parser|
      parser.banner = "Usage: henni run [options] RELATIVE_FILE.rb"
      parser.on("--runner NAME", %w[auto both rspec minitest]) { |value| runner = value }
      parser.on("--rspec-pattern GLOB") { |value| spec_pattern = value }
      parser.on("--minitest-pattern GLOB") { |value| test_pattern = value }
      parser.on("--exclude GLOB", "Exclude a project-relative path (repeatable)") { |glob| excludes << glob }
      parser.on("--timeout SECONDS", Float) { |seconds| timeout = seconds }
    end
    if args == ["--help"] || args == ["run", "--help"]
      puts options
      return 0
    end
    raise ArgumentError, options.banner unless args.shift == "run"
    options.parse!(args)
    raise ArgumentError, options.banner unless args.size == 1
    raise ArgumentError, "timeout must be positive and finite" unless timeout.finite? && timeout.positive?
    target = Pathname.new(args.first).cleanpath.to_s
    unless target.end_with?(".rb") && !Pathname.new(target).absolute? && !target.start_with?("../")
      raise ArgumentError, "expected a project-relative Ruby file"
    end

    input = Snapshot.new(excludes)
    raise ArgumentError, "target is excluded from snapshot: #{target}" if input.excluded?(target, root: Dir.pwd)

    report = { schema_version: 1, target: target, mutations: [], complete: false }
    Dir.mktmpdir("henni-input") do |tmp|
      base = File.join(File.realpath(tmp), "project")
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      input.copy(Dir.pwd, base)
      report[:duration] = { snapshot_seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started }
      source = File.binread(File.join(base, target))
      planner = Planner.new(target, source)
      report[:mutations] = planner.plan.map { |mutation| mutation.merge(status: "pending") }
      unless report[:mutations].empty?
        suites = Suites.discover(base, runner, spec_pattern, test_pattern)
        raise ArgumentError, "no RSpec or Minitest suite found" if suites.empty?
        report[:runners] = suites.keys
        executor = Executor.new(base, target, timeout, suites)
        baseline = report[:baseline] = executor.run(source)
        if baseline[:status] == "passed"
          report[:mutations].each do |mutation|
            changed = planner.apply(mutation)
            execution = if Prism.parse(changed, filepath: target, version: "current").success?
                          executor.run(changed, baseline: baseline)
                        else
                          { status: "invalid", reason: "mutated source failed to parse" }
                        end
            mutation.merge!(execution)
          end
        end
      end
    end
    counts = report[:mutations].map { |mutation| mutation[:status] }.tally
    report[:counts] = counts
    report[:complete] = (counts.keys - %w[killed survived invalid]).empty?
    puts JSON.pretty_generate(report)
    return 2 unless report[:complete]
    counts.key?("survived") ? 1 : 0
  rescue StandardError => e
    message = e.message.encode("UTF-8", invalid: :replace, undef: :replace).scrub
    failure = { schema_version: 1, complete: false, error: message }
    begin
      puts JSON.pretty_generate((report || {}).merge(failure))
    rescue JSON::GeneratorError, EncodingError
      # A path or a diagnostic in the partial report may itself be invalid UTF-8.
      puts JSON.pretty_generate(failure)
    end
    2
  rescue Interrupt
    puts JSON.pretty_generate((report || { schema_version: 1 }).merge(complete: false, error: "interrupted"))
    130
  end
end
