require "fileutils"
require "json"
require "socket"
require "open3"
require "tmpdir"
require "henni"

RSpec.describe "henni run" do
  let(:cli) { File.expand_path("../exe/henni", __dir__) }
  let(:target) { "lib/discount.rb" }
  let(:spec_path) { File.join(@project, "spec/discount_spec.rb") }

  around do |example|
    Dir.mktmpdir do |tmp|
      @project = File.join(tmp, "project")
      FileUtils.cp_r(File.expand_path("../examples/boundary", __dir__), @project)
      example.run
    end
  end

  def run_cli(*options)
    output, log, result = Open3.capture3(RbConfig.ruby, cli, "run", *options, target, chdir: @project)
    [result.exitstatus, JSON.parse(output)]
  rescue JSON::ParserError
    raise "Invalid report: #{output}\n#{log}"
  end

  it "shows the same mutation surviving and then killed by a boundary assertion" do
    path = File.join(@project, target)
    original = File.binread(path)
    code, weak = run_cli
    expect(code).to eq(1)
    expect(weak.fetch("counts")).to eq("survived" => 1)
    File.open(spec_path, "a") do |file|
      file.puts 'RSpec.describe(Discount) { it("includes the threshold") { expect(Discount.eligible?(1_000)).to be(true) } }'
    end
    code, strong = run_cli
    expect(code).to eq(0)
    expect(strong.fetch("counts")).to eq("killed" => 1)
    expect(strong["mutations"].first["id"]).to eq(weak["mutations"].first["id"])
    expect(File.binread(path)).to eq(original)
  end

  it "keeps internal links in the worker and skips Unix sockets" do
    source = File.join(@project, target)
    original = File.binread(source)
    alias_path = File.join(@project, "lib/alias.rb")
    File.symlink(source, alias_path)
    File.symlink(source, File.join(@project, "lib/second_alias.rb"))
    File.write(spec_path, <<~SPEC)
      require_relative "../lib/alias"
      RSpec.describe(Discount) { it { expect(Discount.eligible?(1_000)).to be(true) } }
    SPEC
    UNIXServer.open(File.join(@project, "puma.sock")) do
      code, report = run_cli
      expect([code, report["counts"]]).to eq([0, { "killed" => 1 }]), report.inspect
    end
    expect(File.binread(source)).to eq(original)
    expect(File.readlink(alias_path)).to eq(source)
  end

  it "stops before following a link to external data" do
    File.symlink(Dir.tmpdir, File.join(@project, "outside"))
    code, report = run_cli
    expect(code).to eq(2)
    expect(report.fetch("error")).to include("outside snapshot inputs")
  end

  it "leaves the mutation pending on baseline failure" do
    File.write(spec_path, "raise 'boot failed'")
    code, report = run_cli
    expect([code, report["complete"], report.dig("baseline", "status")]).to eq([2, false, "error"])
    expect(report.fetch("counts")).to eq("pending" => 1)
  end

  it "rejects zero examples and a suite that never loads the target" do
    ["", 'RSpec.describe { it { expect(true).to be(true) } }'].each do |spec|
      File.write(spec_path, spec)
      code, report = run_cli
      expect([code, report.dig("baseline", "status")]).to eq([2, "error"])
    end
  end

  it "keeps an unexpected runtime error separate from an expectation failure" do
    File.open(spec_path, "a") do |file|
      file.puts 'RSpec.describe { it { raise IOError unless Discount.eligible?(1_000) } }'
    end
    code, report = run_cli
    expect([code, report.fetch("counts")]).to eq([2, { "error" => 1 }])
  end

  it "does not declare survival when the mutant silently drops an example" do
    File.open(spec_path, "a") do |file|
      file.puts <<~SPEC
        RSpec.describe Discount do
          if Discount.eligible?(1_000)
            it("handles a higher price") { expect(Discount.eligible?(2_000)).to be(true) }
          end
        end
      SPEC
    end
    code, report = run_cli
    expect(code).to eq(2)
    expect(report.dig("baseline", "example_ids").size).to eq(2)
    expect(report.fetch("mutations").first).to include("status" => "error", "reason" => "RSpec did not run the expected examples")
  end

  it "reports a deadline independently of expectation failures" do
    File.open(spec_path, "a") { |file| file.puts "sleep 20" }
    code, report = run_cli("--timeout", "0.5")
    expect([code, report.dig("baseline", "status")]).to eq([2, "timeout"])
  end

  it "uses byte offsets inside method bodies" do
    source = "TOP = 1 >= 2\ndef 境界(値) = 値 <= 2 # <=\n".b
    planner = Henni::Planner.new("lib/example.rb", source)
    mutations = planner.plan
    expect(mutations.size).to eq(1)
    expect(planner.apply(mutations.first)).to eq("TOP = 1 >= 2\ndef 境界(値) = 値 < 2 # <=\n".b)
  end
end
