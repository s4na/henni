require "bundler"
require "fileutils"
require "tmpdir"

module Henni
  class Executor
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
        status = execute(name, pattern, work, result_path)
        return { status: "timeout", reason: "#{name} exceeded #{@timeout}s" } unless status
        return { status: "error", reason: "#{name} exited without results (#{status})" } unless File.file?(result_path)

        result = JSON.parse(File.read(result_path), symbolize_names: true)
        classify(name, result, status, Digest::SHA256.hexdigest(source), previous)
      end
    end

    def execute(name, pattern, work, result_path)
      env = {}
      env["PARALLEL_WORKERS"] = "1" if name == "minitest"
      gemfile = ENV["BUNDLE_GEMFILE"]
      if gemfile && File.identical?(File.dirname(File.expand_path(gemfile)), Dir.pwd)
        env["BUNDLE_GEMFILE"] = File.join(work, File.basename(gemfile))
        if ENV["BUNDLE_LOCKFILE"]
          lockfile = File.realdirpath(ENV.fetch("BUNDLE_LOCKFILE"))
          prefix = File.realpath(Dir.pwd) + "/"
          raise ArgumentError, "bundle lockfile must be inside the project" unless lockfile.start_with?(prefix)
          env["BUNDLE_LOCKFILE"] = File.join(work, lockfile.delete_prefix(prefix))
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
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
      finished = nil
      loop do
        finished = Process.waitpid2(pid, Process::WNOHANG)
        return finished.last if finished
        return nil if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.02
      end
    ensure
      if pid
        begin
          Process.kill("TERM", -pid)
          sleep 0.1
          # Darwin can report EPERM for a group containing only a zombie.
          Process.waitpid(pid, Process::WNOHANG) unless finished
          Process.kill("KILL", -pid)
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

    def classify(name, result, status, digest, previous)
      label = name == "rspec" ? "RSpec" : "Minitest"
      examples = result.fetch(:examples)
      ids = examples.map { |example| example.fetch(:id) }.sort
      failures = examples.select { |example| example[:status] == "failed" }
      reason = if !status.exited? || status.exitstatus != result[:exit_code] || result[:suite_error]
                 "#{label} process or suite error"
               elsif digest != result[:digest] || (previous && previous[:loaded] != result[:loaded])
                 "target digest or require path mismatch"
               elsif result[:dry_run] || ids.empty? || ids != result.fetch(:expected_ids).sort || (previous && ids != previous[:example_ids])
                 "#{label} did not run the expected examples"
               elsif examples.any? { |example| !%w[passed failed].include?(example[:status]) }
                 "pending or incomplete example"
               elsif !failures.empty?
                 "baseline or non-expectation failure" unless previous && result[:loaded] && failures.all? { |example| example[:assertion] } && !status.success?
               elsif !status.success?
                 "#{label} exited unsuccessfully"
               end
      verdict = if reason then "error"
                elsif !previous then "passed"
                elsif failures.empty? then "survived"
                else "killed"
                end
      { status: verdict, reason: reason, digest: result[:digest], loaded: result[:loaded], example_ids: ids,
        failures: failures.map { |example| example.slice(:id, :exception) } }.compact
    end
  end
end
