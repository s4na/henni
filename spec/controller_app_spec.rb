require "fileutils"
require "json"
require "open3"
require "tmpdir"

RSpec.describe "henni run against a Rails controller" do
  def run_controller_app(runner, exit_code)
    fixture = File.expand_path("../examples/controller_app", __dir__)
    Dir.mktmpdir do |tmp|
      app = File.join(tmp, "quotes")
      FileUtils.cp_r(fixture, app)
      yield app if block_given?
      env = { "BUNDLE_GEMFILE" => Bundler.default_gemfile.to_s, "RAILS_ENV" => "test", "RACK_ENV" => "test" }
      output, log, status = Open3.capture3(env, "bundle", "exec", "henni", "run", "--runner", runner, "app.rb", chdir: app)
      expect(status.exitstatus).to eq(exit_code), "#{output}\n#{log}"
      JSON.parse(output)
    end
  end

  # Each suite owns a different boundary. The other suite still exercises the
  # endpoint, so a surviving mutation there cannot be explained by a missing load.
  [
    ["rspec", 1, { ">" => "survived", ">=" => "killed" }],
    ["minitest", 1, { ">" => "killed", ">=" => "survived" }],
    ["both", 0, { ">" => "killed", ">=" => "killed" }]
  ].each do |runner, exit_code, verdicts|
    it "reports the controller boundaries detected by --runner #{runner}" do
      report = run_controller_app(runner, exit_code)
      suites = runner == "both" ? %w[rspec minitest] : [runner]
      expect(report).to include("complete" => true, "runners" => suites, "counts" => verdicts.values.tally)
      baseline = report.fetch("baseline").fetch("suites")
      expect(baseline.keys).to match_array(suites)
      expected_ids = {
        "rspec" => (1..5).map { |i| "./spec/requests/quotes_spec.rb[1:#{i}]" },
        "minitest" => %w[QuotesTest#test_accepts_maximum_quantity QuotesTest#test_accepts_minimum_quantity
                         QuotesTest#test_rejects_missing_or_invalid_quantity]
      }
      suites.each do |suite|
        expect(baseline.fetch(suite)).to include("loaded" => true, "status" => "passed")
        expect(baseline.fetch(suite).fetch("example_ids")).to match_array(expected_ids.fetch(suite))
      end

      mutations = report.fetch("mutations")
      expect(mutations.map { |m| m.fetch("before") }).to match_array(verdicts.keys)
      mutations.each do |mutation|
        operator = mutation.fetch("before")
        expect(mutation).to include("method" => "create", "status" => verdicts.fetch(operator))
        suites.each do |suite|
          result = mutation.fetch("suites").fetch(suite)
          expect(result.fetch("example_ids")).to match_array(baseline.fetch(suite).fetch("example_ids"))
          failure = case [operator, suite]
                    when [">=", "rspec"] then "./spec/requests/quotes_spec.rb[1:2]"
                    when [">", "minitest"] then "QuotesTest#test_accepts_maximum_quantity"
                    end
          expect(result.fetch("status")).to eq(failure ? "killed" : "survived")
          expect(result.fetch("failures").map { |item| item.fetch("id") }).to eq(Array(failure))
        end
      end
    end
  end

  it "leaves mutations pending when an initializer prevents the application from booting" do
    report = run_controller_app("both", 2) do |app|
      initializers = File.join(app, "config", "initializers")
      FileUtils.mkdir_p(initializers)
      File.write(File.join(initializers, "unavailable.rb"), "raise 'startup failed'\n")
    end
    expect(report).to include("complete" => false, "counts" => { "pending" => 2 })
    expect(report.dig("baseline", "suites").transform_values { |s| s.fetch("status") })
      .to eq("rspec" => "error", "minitest" => "error")
  end
end
