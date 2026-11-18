require "fileutils"
require "open3"
require "tmpdir"

RSpec.describe "stamping a main push" do
  it "records the push in the gem metadata and lockfile and preserves the result on a retry" do
    root = File.expand_path("..", __dir__)
    Dir.mktmpdir do |dir|
      FileUtils.cp(%w[VERSION Gemfile.lock henni.gemspec].map { |f| File.join(root, f) }, dir)
      current = File.readlines(File.join(dir, "VERSION"), chomp: true).first
      version = Gem::Version.new(current).segments
      next_patch = version.last + 1
      next_version = [*version.take(2), next_patch].join(".")
      env = { "GITHUB_RUN_NUMBER" => next_patch.to_s, "GITHUB_SHA" => "a" * 40 }
      script = File.join(root, "script/stamp_version.rb")
      lock_path = File.join(dir, "Gemfile.lock")
      original_lock = File.read(lock_path)
      2.times do
        output, status = Open3.capture2e(env, RbConfig.ruby, script, chdir: dir)
        expect(status).to be_success, output
        spec = Gem::Specification.load(File.join(dir, "henni.gemspec"))
        expect(spec.version.to_s).to eq(next_version)
        expect(spec.metadata.fetch("source_revision")).to eq(env.fetch("GITHUB_SHA"))
        lock = File.read(lock_path)
        expect(lock.lines.grep(/^ +henni \(/).map(&:strip)).to all(eq("henni (#{next_version})"))
        expect(lock.gsub("henni (#{next_version})", "henni (#{current})")).to eq(original_lock)
      end

      # A different source cannot claim the same published version.
      _, status = Open3.capture2e(env.merge("GITHUB_SHA" => "b" * 40), RbConfig.ruby, script, chdir: dir)
      expect(status).not_to be_success
      expect(File.readlines(File.join(dir, "VERSION"), chomp: true)).to eq([next_version, "a" * 40])
    end
  end
end
