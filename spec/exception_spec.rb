require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "henni"

RSpec.describe "mutation runtime exceptions" do
  let(:cli) { File.expand_path("../exe/henni", __dir__) }

  around do |example|
    Dir.mktmpdir("henni-exception-spec") do |root|
      @project = root
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib/name.rb"), <<~RUBY)
        module Name
          def self.of(user)
            user == nil ? "guest" : user.fetch(:name)
          end
        end
      RUBY
      example.run
    end
  end

  def run_report(runner)
    output, log, result = Open3.capture3(RbConfig.ruby, cli, "run", "--runner", runner,
                                        "lib/name.rb", chdir: @project)
    [result.exitstatus, JSON.parse(output)]
  rescue JSON::ParserError
    raise "Invalid report: #{output}\n#{log}"
  end

  it "confirms the original RSpec suite before classifying a NoMethodError as killed" do
    FileUtils.mkdir_p(File.join(@project, "spec"))
    File.write(File.join(@project, "spec/name_spec.rb"), <<~RUBY)
      require_relative "../lib/name"
      RSpec.describe(Name) { it { expect(Name.of(nil)).to eq("guest") } }
    RUBY
    code, report = run_report("rspec")
    expect(code).to eq(0)
    mutation = report.fetch("mutations").first
    expect(mutation).to include("status" => "killed", "killed_by" => "exception")
    suite = mutation.fetch("suites").fetch("rspec")
    expect(suite.fetch("failures").first.fetch("exception")).to eq("NoMethodError")
    expect(suite.fetch("baseline_recheck")).to include("status" => "passed")
  end

  it "also detects runtime exceptions through Minitest's UnexpectedError wrapper" do
    FileUtils.mkdir_p(File.join(@project, "test"))
    File.write(File.join(@project, "test/name_test.rb"), <<~RUBY)
      require "minitest/autorun"
      require_relative "../lib/name"
      class NameTest < Minitest::Test
        def test_guest
          assert_equal "guest", Name.of(nil)
        end
      end
    RUBY
    code, report = run_report("minitest")
    expect(code).to eq(0)
    suite = report.fetch("mutations").first.fetch("suites").fetch("minitest")
    expect(suite).to include("status" => "killed", "killed_by" => "exception")
    expect(suite.fetch("baseline_recheck")).to include("status" => "passed")
  end

  it "does not hide a Minitest teardown infrastructure failure behind a runtime exception" do
    FileUtils.mkdir_p(File.join(@project, "test"))
    File.write(File.join(@project, "test/name_test.rb"), <<~RUBY)
      require "minitest/autorun"
      require_relative "../lib/name"
      class NameTest < Minitest::Test
        def test_guest
          assert_equal "guest", Name.of(nil)
        rescue NoMethodError
          @runtime_failure = true
          raise
        end

        def teardown
          raise IOError, "unavailable resource" if @runtime_failure
        end
      end
    RUBY
    code, report = run_report("minitest")
    expect(code).to eq(2)
    suite = report.fetch("mutations").first.fetch("suites").fetch("minitest")
    expect(suite.fetch("status")).to eq("error")
    expect(suite.fetch("failures").first.fetch("causes").map { |cause| cause.fetch("exception") })
      .to contain_exactly("NoMethodError", "IOError")
    expect(suite).not_to have_key("baseline_recheck")
  end

  it "keeps a runtime exception inconclusive when the original suite no longer passes" do
    Dir.mktmpdir("henni-baseline-state") do |state|
      marker = File.join(state, "runs")
      FileUtils.mkdir_p(File.join(@project, "spec"))
      File.write(File.join(@project, "spec/name_spec.rb"), <<~RUBY)
        require_relative "../lib/name"
        marker = #{marker.inspect}
        count = File.exist?(marker) ? File.read(marker).to_i + 1 : 1
        File.write(marker, count)
        RSpec.describe(Name) do
          it do
            raise "unstable baseline" if count > 2
            expect(Name.of(nil)).to eq("guest")
          end
        end
      RUBY
      code, report = run_report("rspec")
      expect(code).to eq(2)
      mutation = report.fetch("mutations").first
      expect(mutation).to include("status" => "error",
                                 "reason" => "original suite did not reproduce the passing baseline")
      expect(mutation).not_to have_key("killed_by")
      expect(mutation.fetch("suites").fetch("rspec").fetch("baseline_recheck")["status"]).to eq("error")
    end
  end

  it "keeps infrastructure failures and suite setup failures inconclusive" do
    FileUtils.mkdir_p(File.join(@project, "spec"))
    [
      'RSpec.describe(Name) { it { raise IOError if Name.of(nil) == "guest" } }',
      'RSpec.configure { |config| config.before(:suite) { Name.of(nil) } }; RSpec.describe(Name) { it { expect(true).to be(true) } }'
    ].each do |body|
      File.write(File.join(@project, "spec/name_spec.rb"), "require_relative \"../lib/name\"\n" + body)
      code, report = run_report("rspec")
      expect(code).to eq(2)
      expect(report.fetch("complete")).to be(false)
      expect(report.fetch("counts").keys).not_to include("killed")
    end
  end
end

RSpec.describe Henni::Executor do
  let(:executor) { described_class.new("snapshot", "lib/name.rb", 60, { "rspec" => nil }) }
  let(:status) { instance_double(Process::Status, success?: false, exited?: true, exitstatus: 1) }
  let(:previous) { { status: "passed", loaded: true, digest: "original", example_ids: ["example"] } }
  let(:result) do
    { loaded: true, digest: "changed", exit_code: 1, expected_ids: ["example"],
      examples: [{ id: "example", status: "failed", assertion: false, exception: "TypeError" }] }
  end

  it "requires the same complete example set, target digest, and successful baseline" do
    [
      result.merge(digest: "other"),
      result.merge(suite_error: true),
      result.merge(expected_ids: ["example", "missing"]),
      result.merge(examples: result[:examples] + [{ id: "skipped", status: "pending" }])
    ].each do |report|
      expect(executor.send(:classify, "rspec", report, status, "changed", previous)[:status]).to eq("error")
    end
    expect(executor.send(:classify, "rspec", result, status, "changed", previous.merge(status: "error"))[:status]).to eq("error")
  end

  it "does not classify unrecognized or infrastructure exception names as killed" do
    %w[IOError Errno::ECONNREFUSED ActiveRecord::ConnectionNotEstablished RuntimeError].each do |name|
      result[:examples].first[:exception] = name
      expect(executor.send(:classify, "rspec", result, status, "changed", previous)[:status]).to eq("error")
    end
  end
end
