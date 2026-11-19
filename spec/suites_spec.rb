require "fileutils"
require "json"
require "open3"
require "tmpdir"

RSpec.describe "henni suite discovery and verdicts" do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      write("lib/threshold.rb", "def eligible?(n) = n >= 10")
      example.run
    end
  end

  def write(path, source)
    file = File.join(@dir, path)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, source)
  end

  def minitest(body, path: "test/nested/threshold_test.rb")
    write(path, <<~TEST)
      require "minitest/autorun"
      require "threshold"
      class BoundaryTest < Minitest::Test
        def test_threshold
          #{body}
        end
      end
    TEST
  end

  def rspec(body, path: "spec/nested/threshold_spec.rb")
    write(path, "require 'threshold'\nRSpec.describe('boundary') { it { #{body} } }")
  end

  def run_cli(code, *options)
    cli = File.expand_path("../exe/henni", __dir__)
    output, log, status = Open3.capture3(RbConfig.ruby, cli, "run", *options, "lib/threshold.rb", chdir: @dir)
    expect(status.exitstatus).to eq(code), "#{output}\n#{log}"
    JSON.parse(output)
  end

  it "discovers Minitest alone and distinguishes an assertion from a surviving mutation" do
    minitest("assert eligible?(10)")
    report = run_cli(0)
    expect(report["runners"]).to eq(["minitest"])
    expect(report.dig("mutations", 0, "failures")).to eq([{ "id" => "BoundaryTest#test_threshold", "exception" => "Minitest::Assertion" }])
    minitest("assert eligible?(11)")
    expect(run_cli(1)["counts"]).to eq("survived" => 1)
  end

  %w[rspec minitest].each do |runner|
    it "rejects a regenerated target with #{runner}, including when its bytes are restored" do
      path = runner == "rspec" ? "spec/regenerated_spec.rb" : "test/regenerated_test.rb"
      test = if runner == "rspec"
               'RSpec.describe("threshold") { it { expect(eligible?(10)).to be(true) } }'
             else
               "class BoundaryTest < Minitest::Test; def test_threshold; assert eligible?(10); end; end"
             end
      write(path, <<~RUBY)
        target = File.expand_path("../lib/threshold.rb", __dir__)
        bytes = File.binread(target)
        if bytes.include?(" > ")
          # Generate the original implementation, require it, then restore the mutant.
          File.write(target + ".new", bytes.sub(" > ", " >= "))
          File.rename(target + ".new", target)
          require target
          File.binwrite(target, bytes)
        else
          require target
        end
        #{test}
      RUBY
      report = run_cli(2, "--runner", runner)
      expect(report.dig("baseline", "status")).to eq("passed")
      expect(report.dig("mutations", 0, "reason")).to eq("target file changed during the suite")
      expect(report.fetch("counts")).to eq("error" => 1)
    end
  end

  it "runs a passing suite that never requires the target alongside a suite that detects it" do
    write("spec/other_spec.rb", "RSpec.describe('another unit') { it { expect(2 + 2).to eq(4) } }")
    minitest("assert eligible?(10)")
    report = run_cli(0)
    expect(report.dig("baseline", "suites", "rspec", "loaded")).to be(false)
    expect(report["counts"]).to eq("killed" => 1)
  end

  it "gives a Minitest runtime error precedence over an RSpec kill" do
    rspec("expect(eligible?(10)).to be(true)")
    minitest('raise IOError, "test infrastructure unavailable" unless eligible?(10)')
    report = run_cli(2)
    expect(report["counts"]).to eq("error" => 1)
    suites = report.dig("mutations", 0, "suites")
    expect(suites.dig("rspec", "status")).to eq("killed")
    expect(suites.dig("minitest", "failures", 0, "exception")).to eq("IOError")
  end

  it "classifies RSpec mock and grouped expectation failures without masking other exceptions" do
    rspec("allow(self).to receive(:notify); expect(self).to receive(:notify); notify if eligible?(10)")
    expect(run_cli(0)["counts"]).to eq("killed" => 1)
    rspec("aggregate_failures { expect(eligible?(10)).to be(true); expect(eligible?(10)).to be_truthy }")
    expect(run_cli(0)["counts"]).to eq("killed" => 1)
    rspec('aggregate_failures { expect(eligible?(10)).to be(true); raise IOError unless eligible?(10) }')
    expect(run_cli(2)["counts"]).to eq("error" => 1)
  end

  it "marks skips, zero tests and missing selected suites as incomplete" do
    minitest("skip")
    expect(run_cli(2).dig("baseline", "reason")).to eq("pending or incomplete example")
    write("test/nested/threshold_test.rb", "require 'threshold'")
    expect(run_cli(2).dig("baseline", "reason")).to eq("Minitest did not run the expected examples")
    rspec("expect(eligible?(11)).to be(true)")
    expect(run_cli(2, "--minitest-pattern", "custom/*_test.rb")["complete"]).to be(false)
  end

  it "supports nonstandard suite paths and an explicit runner" do
    minitest("assert eligible?(10)", path: "checks/unit/case.rb")
    rspec("expect(eligible?(11)).to be(true)", path: "checks/spec/case.rb")
    options = ["--rspec-pattern", "checks/spec/*.rb", "--minitest-pattern", "checks/unit/*.rb"]
    expect(run_cli(0, *options)["runners"]).to eq(%w[rspec minitest])
    expect(run_cli(1, "--runner", "rspec", *options)["runners"]).to eq(["rspec"])
  end

  it "respects the RSpec default path and detects examples omitted by a focus filter" do
    write(".rspec", "--default-path behavior")
    rspec("expect(eligible?(10)).to be(true)", path: "behavior/boundary_spec.rb")
    expect(run_cli(0)["counts"]).to eq("killed" => 1)
    write("behavior/focus_spec.rb", <<~SPEC)
      RSpec.configure { |config| config.filter_run_when_matching :focus }
      RSpec.describe("focused unit") { it("passes", :focus) { expect(true).to be(true) } }
    SPEC
    expect(run_cli(2).dig("baseline", "reason")).to eq("RSpec did not run the expected examples")
  end
end
