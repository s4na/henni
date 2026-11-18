require "fileutils"
require "tmpdir"
require "json"
require "optparse"
require "pathname"
require_relative "henni/planner"
require_relative "henni/suites"
require_relative "henni/executor"

module Henni
  OMIT = %w[.git .bundle vendor/bundle henni-report].freeze

  def self.snapshot(root, dest)
    raise ArgumentError, "temporary directory must be outside the project" if dest.start_with?(root + "/") || root == "/"

    root = File.realpath(root)
    Dir.mkdir(dest)
    copy = lambda do |relative|
      Dir.each_child(File.join(root, relative)) do |name|
        path = File.join(relative, name).delete_prefix("/")
        next if OMIT.include?(path)
        source = File.join(root, path)
        output = File.join(dest, path)
        case File.lstat(source).ftype
        when "directory"
          Dir.mkdir(output)
          copy.call(path)
        when "file"
          FileUtils.copy_file(source, output, true)
        when "link"
          resolved = File.realpath(source)
          referent = Pathname.new(resolved).relative_path_from(Pathname.new(root)).to_s
          if referent == ".." || referent.start_with?("../") || OMIT.any? { |entry| referent == entry || referent.start_with?(entry + "/") }
            raise ArgumentError, "link points outside snapshot inputs: #{path}"
          end
          # An absolute source link must still resolve inside every worker copy.
          link = Pathname.new(resolved).relative_path_from(Pathname.new(File.dirname(source)))
          File.symlink(link, output)
        when "socket", "fifo"
          warn "henni: skipping runtime endpoint #{path}"
        else
          raise ArgumentError, "unsupported project entry: #{path}"
        end
      end
    end
    copy.call("")
  end

  def self.run(args)
    timeout = 60.0
    runner = "auto"
    spec_pattern = nil
    test_pattern = nil
    options = OptionParser.new do |parser|
      parser.banner = "Usage: henni run [options] RELATIVE_FILE.rb"
      parser.on("--runner NAME", %w[auto both rspec minitest]) { |value| runner = value }
      parser.on("--rspec-pattern GLOB") { |value| spec_pattern = value }
      parser.on("--minitest-pattern GLOB") { |value| test_pattern = value }
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

    report = { schema_version: 1, target: target, mutations: [], complete: false }
    Dir.mktmpdir("henni-input") do |tmp|
      base = File.join(File.realpath(tmp), "project")
      snapshot(Dir.pwd, base)
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
  rescue ArgumentError, OptionParser::ParseError, SystemCallError, JSON::ParserError => e
    puts JSON.pretty_generate((report || { schema_version: 1 }).merge(complete: false, error: e.message))
    2
  rescue Interrupt
    puts JSON.pretty_generate((report || { schema_version: 1 }).merge(complete: false, error: "interrupted"))
    130
  end
end
