require "bundler"
require "digest"
require "fileutils"
require "tmpdir"

module Henni
  class Executor
    MIN_MUTATION_TIMEOUT = 1.0
    BASELINE_TIMEOUT_FACTOR = 5.0
    RUNTIME_FAILURES = %w[NoMethodError TypeError ArgumentError NameError IndexError KeyError RangeError ZeroDivisionError FrozenError].freeze

    def initialize(snapshot, target, timeout, suites)
      @snapshot = snapshot
      @target = target
      @timeout = timeout
      @suites = suites
    end

    def run(source, baseline: nil)
      suites = @suites.to_h do |name, pattern|
        previous = baseline&.fetch(:suites)&.fetch(name)
        [name, run_suite(name, pattern, source, previous)]
      end
      results = suites.values
      problem = results.find { |result| %w[error timeout].include?(result[:status]) }
      loaded = results.any? { |result| result[:loaded] }
      verdict = if problem
                  problem.slice(:status, :reason)
                elsif !loaded
                  { status: "error", reason: "target was not loaded by any suite" }
                elsif !baseline
                  { status: "passed" }
                elsif results.any? { |result| result[:status] == "killed" }
                  { status: "killed" }
                else
                  { status: "survived" }
                end
      if verdict[:status] == "killed"
        verdict[:killed_by] = results.any? { |result| result[:killed_by] == "exception" } ? "exception" : "assertion"
      end
      verdict.merge(suites: suites, loaded: loaded, digest: results.first[:digest],
                    example_ids: results.flat_map { |result| result.fetch(:example_ids, []) },
                    failures: results.flat_map { |result| result.fetch(:failures, []) })
    end

    private

    def run_suite(name, pattern, source, previous)
      Dir.mktmpdir("henni-run") do |tmp|
        work = File.join(tmp, "project")
        FileUtils.cp_r(@snapshot, work)
        File.binwrite(File.join(work, @target), source)
        result_path = File.join(tmp, "result.json")
        timeout, baseline_duration = timeout_for(previous)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        status = execute(name, pattern, work, result_path, timeout)
        timing = { duration_seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
                   timeout_seconds: timeout, timeout_source: baseline_duration ? "baseline" : "configured" }
        timing[:baseline_duration_seconds] = baseline_duration if baseline_duration
        unless status
          phase = previous ? "mutation after a passing baseline" : "baseline"
          return timing.merge(status: "timeout", reason: "#{name} #{phase} exceeded #{timeout}s")
        end
        unless File.file?(result_path)
          return timing.merge(status: "error", reason: "#{name} exited without results (#{status})")
        end

        result = JSON.parse(File.read(result_path), symbolize_names: true)
        classified = classify(name, result, status, Digest::SHA256.hexdigest(source), previous).merge(timing)
        if classified[:status] == "killed" && classified[:killed_by] == "exception"
          original = File.binread(File.join(@snapshot, @target))
          confirmation = run_suite(name, pattern, original, nil)
          classified[:baseline_recheck] = confirmation
          unless confirmation[:status] == "passed" && confirmation[:digest] == previous[:digest] &&
                 confirmation[:loaded] == previous[:loaded] && confirmation[:example_ids] == previous[:example_ids]
            classified[:status] = "error"
            classified[:reason] = "original suite did not reproduce the passing baseline"
            classified.delete(:killed_by)
          end
        end
        classified
      end
    end

    def timeout_for(previous)
      duration = previous && previous[:duration_seconds]
      return [@timeout, nil] unless previous && previous[:status] == "passed" && duration.is_a?(Numeric) && duration.finite? && duration.positive?

      timeout = [@timeout, [MIN_MUTATION_TIMEOUT, duration * BASELINE_TIMEOUT_FACTOR].max].min
      [timeout, duration]
    end

    def project_relative_path(path)
      expanded = File.expand_path(path)
      absolute = File.join(File.realpath(File.dirname(expanded)), File.basename(expanded))
      prefix = File.realpath(Dir.pwd) + "/"
      absolute.delete_prefix(prefix) if absolute.start_with?(prefix)
    end

    def execute(name, pattern, work, result_path, timeout)
      env = {}
      env["PARALLEL_WORKERS"] = "1" if name == "minitest"
      gemfile = ENV["BUNDLE_GEMFILE"]
      if gemfile && (relative = project_relative_path(gemfile))
        env["BUNDLE_GEMFILE"] = File.join(work, relative)
        if ENV["BUNDLE_LOCKFILE"]
          lockfile = project_relative_path(ENV.fetch("BUNDLE_LOCKFILE"))
          raise ArgumentError, "bundle lockfile must be inside the project" unless lockfile
          env["BUNDLE_LOCKFILE"] = File.join(work, lockfile)
        end
        %i[with without only].each do |setting|
          groups = Array(Bundler.settings[setting])
          env["BUNDLE_#{setting.upcase}"] = groups.join(":")
        end
        path = Bundler.settings.path
        env["BUNDLE_PATH"] = File.expand_path(path.base_path, Bundler.root) unless path.use_system_gems?
      end
      worker = File.expand_path("#{name}_worker.rb", __dir__)
      pid = Process.spawn(env, RbConfig.ruby, "-Ilib", worker, @target, result_path, *Array(pattern),
                          chdir: work, pgroup: true, out: :err)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        finished = Process.waitpid2(pid, Process::WNOHANG)
        return finished.last if finished
        return nil if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.02
      end
    ensure
      if pid
        begin
          signal_group("TERM", pid)
          sleep 0.1
          signal_group("KILL", pid)
        rescue Errno::ESRCH
          # The process group has already exited.
        end
        begin
          Process.wait(pid)
        rescue Errno::ECHILD
          # Already reaped on normal completion.
        end
      end
    end

    def signal_group(signal, pid)
      Process.kill(signal, -pid)
    rescue Errno::EPERM => denied
      # Darwin may return EPERM for a group containing only a zombie. Reap
      # the leader and retry; a live group's real permission error matters.
      begin
        raise denied unless Process.waitpid(pid, Process::WNOHANG)
      rescue Errno::ECHILD
        raise denied
      end
      Process.kill(signal, -pid)
    end

    def classify(name, result, status, digest, previous)
      label = name == "rspec" ? "RSpec" : "Minitest"
      examples = result.fetch(:examples)
      ids = examples.map { |example| example.fetch(:id) }.sort
      failures = examples.select { |example| example[:status] == "failed" }
      detected = previous && previous[:status] == "passed" && result[:loaded] && !status.success? &&
                 failures.all? do |example|
                   causes = example.fetch(:causes, [example])
                   !causes.empty? && causes.all? { |cause| cause[:assertion] || RUNTIME_FAILURES.include?(cause[:exception]) }
                 end
      reason = if !status.exited? || status.exitstatus != result[:exit_code] || result[:suite_error]
                 "#{label} process or suite error"
               elsif digest != result[:digest] || (previous && previous[:loaded] != result[:loaded])
                 "target digest or require path mismatch"
               elsif result[:dry_run] || ids.empty? || ids != result.fetch(:expected_ids).sort || (previous && ids != previous[:example_ids])
                 "#{label} did not run the expected examples"
               elsif examples.any? { |example| !%w[passed failed].include?(example[:status]) }
                 "pending or incomplete example"
               elsif !failures.empty? && !detected
                 "baseline or non-expectation failure"
               elsif failures.empty? && !status.success?
                 "#{label} exited unsuccessfully"
               end
      verdict = if reason then "error"
                elsif !previous then "passed"
                elsif failures.empty? then "survived"
                else "killed"
                end
      killed_by = if verdict == "killed"
                    failures.all? { |example| example[:assertion] } ? "assertion" : "exception"
                  end
      failure_details = failures.map do |example|
        detail = example.slice(:id, :exception)
        causes = example[:causes]
        detail[:causes] = causes if causes && causes.size > 1
        detail
      end
      { status: verdict, killed_by: killed_by, reason: reason, digest: result[:digest], loaded: result[:loaded], example_ids: ids,
        failures: failure_details }.compact
    end
  end
end
