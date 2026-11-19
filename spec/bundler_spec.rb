require "fileutils"
require "json"
require "open3"
require "tmpdir"

RSpec.describe "henni with a nested Gemfile" do
  it "loads a relative path gem and an explicit lockfile from the worker copy" do
    Dir.mktmpdir do |app|
      %w[gemfiles locks spec components/threshold/lib].each { |dir| FileUtils.mkdir_p(File.join(app, dir)) }
      File.write(File.join(app, "components/threshold/threshold.gemspec"), <<~GEMSPEC)
        Gem::Specification.new do |s|
          s.name = "threshold"
          s.version = "1.0"
          s.summary = "Boundary fixture"
          s.authors = ["Example"]
          s.files = ["lib/threshold.rb"]
        end
      GEMSPEC
      target = "components/threshold/lib/threshold.rb"
      File.write(File.join(app, target), "def eligible?(n) = n >= 10")
      gemfile = File.join(app, "gemfiles/ci.gemfile")
      lockfile = File.join(app, "locks/ci.lock")
      File.write(gemfile, <<~GEMFILE)
        source "https://rubygems.org"
        gem "henni", path: ENV.fetch("HENNI_SOURCE")
        gem "threshold", path: "../components/threshold"
        gem "rspec", "~> 3.13"
      GEMFILE
      File.write(File.join(app, "spec/threshold_spec.rb"), <<~RUBY)
        require "threshold"
        RSpec.describe "nested bundle" do
          it do
            expect(Bundler.default_gemfile.realpath).to eq(Pathname("gemfiles/ci.gemfile").realpath)
            expect(Bundler.default_lockfile.realpath).to eq(Pathname("locks/ci.lock").realpath)
            expect(eligible?(10)).to be(true)
          end
        end
      RUBY
      env = { "HENNI_SOURCE" => File.expand_path("..", __dir__), "BUNDLE_GEMFILE" => gemfile,
              "BUNDLE_LOCKFILE" => lockfile, "BUNDLE_FROZEN" => "false" }
      path = Bundler.settings.path
      env["BUNDLE_PATH"] = File.expand_path(path.base_path, Bundler.root) unless path.use_system_gems?
      log, status = Open3.capture2e(env, "bundle", "lock", "--local", chdir: app)
      expect(status).to be_success, log
      original_lock = File.binread(lockfile)
      output, log, status = Open3.capture3(env.merge("BUNDLE_FROZEN" => "true"), "bundle", "exec",
                                           "henni", "run", target, chdir: app)
      expect(status.exitstatus).to eq(0), "#{output}\n#{log}"
      expect(JSON.parse(output)).to include("counts" => { "killed" => 1 })
      expect(File.binread(lockfile)).to eq(original_lock)
    end
  end
end
