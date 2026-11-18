require "fileutils"
require "json"
require "open3"
require "tmpdir"

RSpec.describe "henni run in a Rails application" do
  it "distinguishes detected and surviving model changes across request and browser system specs" do
    fixture = File.expand_path("../test/rails_app", __dir__)
    target = "app/models/offer.rb"
    Dir.mktmpdir do |tmp|
      app = File.join(tmp, "shop")
      FileUtils.cp_r(fixture, app)
      # Resolve the fixture's own bundle before henni copies it into its workers.
      gemfile = File.join(app, "Gemfile")
      File.write(gemfile, "eval_gemfile #{Bundler.default_gemfile.to_s.dump}\n")
      env = { "DATABASE_URL" => nil, "BUNDLE_GEMFILE" => gemfile }
      path = Bundler.settings.path
      env["BUNDLE_PATH"] = File.expand_path(path.base_path, Bundler.root) unless path.use_system_gems?
      lock_log, locked = Open3.capture2e(env, "bundle", "lock", "--local", chdir: app)
      expect(locked).to be_success, lock_log

      output, log, status = Open3.capture3(env, "bundle", "exec", "henni", "run", "--timeout", "90", target, chdir: app)

      expect(status.exitstatus).to eq(1), "#{output}\n#{log}"
      report = JSON.parse(output)
      ids = %w[./spec/requests/offers_spec.rb[1:1] ./spec/system/offers_spec.rb[1:1]]
      expect(report).to include("complete" => true, "counts" => { "killed" => 1, "survived" => 1 })
      expect(report.fetch("baseline")).to include("status" => "passed", "loaded" => true, "example_ids" => ids)
      price, stock = report.fetch("mutations").sort_by { |mutation| mutation.fetch("offset") }
      expect(price).to include("before" => ">=", "after" => ">", "status" => "killed")
      expect(price.fetch("failures").map { |failure| failure.fetch("id") }).to contain_exactly(*ids)
      expect(stock).to include("before" => ">", "after" => ">=", "status" => "survived", "example_ids" => ids)
      expect(File.binread(File.join(app, target))).to eq(File.binread(File.join(fixture, target)))
      expect(Dir.glob(File.join(app, "tmp", "test.sqlite3*"))).to be_empty
    end
  end
end
