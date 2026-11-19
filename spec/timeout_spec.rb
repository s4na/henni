require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "henni"

RSpec.describe "adaptive mutation timeout" do
  it "records baseline timing and limits an endless mutant without counting it as killed" do
    Dir.mktmpdir("henni-timeout-spec") do |project|
      FileUtils.mkdir_p(File.join(project, "lib"))
      FileUtils.mkdir_p(File.join(project, "spec"))
      File.write(File.join(project, "lib/loop.rb"), <<~RUBY)
        module LoopExample
          def self.finish
            loop { break if 1 == 1 }
            true
          end
        end
      RUBY
      File.write(File.join(project, "spec/loop_spec.rb"), <<~RUBY)
        require_relative "../lib/loop"
        RSpec.describe(LoopExample) { it { expect(LoopExample.finish).to be(true) } }
      RUBY
      cli = File.expand_path("../exe/henni", __dir__)
      output, log, result = Open3.capture3(RbConfig.ruby, cli, "run", "--timeout", "10", "lib/loop.rb",
                                          chdir: project)
      report = JSON.parse(output)
      baseline = report.fetch("baseline").fetch("suites").fetch("rspec")
      mutant = report.fetch("mutations").first.fetch("suites").fetch("rspec")
      expect(result.exitstatus).to eq(2), log
      expect(report.fetch("complete")).to be(false)
      expect(report.fetch("counts")).to eq("timeout" => 1)
      expect(baseline).to include("status" => "passed", "timeout_source" => "configured", "timeout_seconds" => 10.0)
      expect(baseline.fetch("duration_seconds")).to be > 0
      expected = [10.0, [1.0, baseline.fetch("duration_seconds") * 5.0].max].min
      expect(mutant).to include("status" => "timeout", "timeout_source" => "baseline",
                               "baseline_duration_seconds" => baseline.fetch("duration_seconds"),
                               "timeout_seconds" => expected)
      expect(mutant.fetch("reason")).to include("mutation after a passing baseline")
      expect(File.read(File.join(project, "lib/loop.rb"))).to include("1 == 1")
    end
  end
end

RSpec.describe Henni::Executor, "timeout policy" do
  let(:executor) { described_class.new("snapshot", "lib/example.rb", 60.0, {}) }

  it "uses the configured ceiling for the baseline and incomplete or missing timings" do
    [nil, { status: "error", duration_seconds: 0.1 }, { status: "passed" },
     { status: "passed", duration_seconds: Float::INFINITY },
     { status: "passed", duration_seconds: 0 }].each do |previous|
      expect(executor.send(:timeout_for, previous)).to eq([60.0, nil])
    end
  end

  it "has a minimum, scales each suite independently, and never exceeds the configured ceiling" do
    [[0.01, 1.0], [2.0, 10.0], [20.0, 60.0]].each do |duration, expected|
      expect(executor.send(:timeout_for, { status: "passed", duration_seconds: duration })).to eq([expected, duration])
    end
    short = described_class.new("snapshot", "lib/example.rb", 0.25, {})
    expect(short.send(:timeout_for, { status: "passed", duration_seconds: 0.01 })).to eq([0.25, 0.01])
  end
end
