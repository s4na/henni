require "fileutils"
require "tmpdir"
require "open3"
require "json"
require "henni"

RSpec.describe Henni::Snapshot do
  around do |example|
    Dir.mktmpdir("henni-snapshot-spec") do |tmp|
      @source = File.join(tmp, "source")
      @dest = File.join(tmp, "dest")
      Dir.mkdir(@source)
      example.run
    end
  end

  def write_input(path)
    output = File.join(@source, path)
    FileUtils.mkdir_p(File.dirname(output))
    File.write(output, "sample")
  end

  it "keeps generated directories empty but preserves test inputs by default" do
    %w[tmp/cache/item log/test.log coverage/report node_modules/example/index.js lib/sample.rb .git/config].each do |path|
      write_input(path)
    end

    described_class.new([]).copy(@source, @dest)

    %w[tmp log coverage].each { |path| expect(Dir.children(File.join(@dest, path))).to be_empty }
    expect(File).to exist(File.join(@dest, "node_modules/example/index.js"))
    expect(File).to exist(File.join(@dest, "lib/sample.rb"))
    expect(File).not_to exist(File.join(@dest, ".git"))
    expect(File).to exist(File.join(@source, "tmp/cache/item"))
  end

  it "preserves regular files and internal links with generated-directory names" do
    write_input("log")
    write_input("var/runtime/input")
    File.symlink("var/runtime", File.join(@source, "tmp"))

    described_class.new([]).copy(@source, @dest)

    expect(File.read(File.join(@dest, "log"))).to eq("sample")
    expect(File.symlink?(File.join(@dest, "tmp"))).to be(true)
    expect(File.read(File.join(@dest, "tmp/input"))).to eq("sample")
    expect(File.realpath(File.join(@dest, "tmp"))).to eq(File.join(@dest, "var/runtime"))
  end

  it "rejects external links with generated-directory names" do
    File.symlink(File.dirname(@source), File.join(@source, "coverage"))

    expect { described_class.new([]).copy(@source, @dest) }.to raise_error(ArgumentError, /outside snapshot inputs/)
  end

  it "rejects dangling links with generated-directory names" do
    File.symlink("missing", File.join(@source, "log"))

    expect { described_class.new([]).copy(@source, @dest) }.to raise_error(Errno::ENOENT)
  end

  it "prunes matching directories and nested files with project-relative patterns" do
    %w[node_modules/example/index.js public/assets/nested/bundle.js public/assets/nested/input.json].each do |path|
      write_input(path)
    end

    described_class.new(["node_modules", "public/**/*.js"]).copy(@source, @dest)

    expect(File).not_to exist(File.join(@dest, "node_modules"))
    expect(File).not_to exist(File.join(@dest, "public/assets/nested/bundle.js"))
    expect(File).to exist(File.join(@dest, "public/assets/nested/input.json"))
  end

  it "rejects a link pointing through an excluded directory" do
    write_input("cache/nested/asset")
    File.symlink("cache/nested/asset", File.join(@source, "alias"))
    input = described_class.new(["cache"])

    expect { input.copy(@source, @dest) }.to raise_error(ArgumentError, /outside snapshot inputs/)
  end

  it "rejects patterns that are not project-relative" do
    expect { described_class.new(["../tmp"]) }.to raise_error(ArgumentError, /project-relative/)
    expect { described_class.new(["/tmp"]) }.to raise_error(ArgumentError, /project-relative/)
  end
  it "applies repeatable CLI exclusions to workers and reports phase timings" do
    FileUtils.cp_r(File.join(__dir__, "../examples/boundary/."), @source)
    write_input("generated/deep/artifact.js")
    write_input("bulky/node_modules/example/index.js")
    File.open(File.join(@source, "spec/discount_spec.rb"), "a") do |file|
      file.puts <<~SPEC
        RSpec.describe "temporary worktree" do
          it "does not copy excluded artifacts" do
            expect(File).not_to exist("generated/deep/artifact.js")
            expect(File).not_to exist("bulky/node_modules")
          end
        end
      SPEC
    end
    cli = File.expand_path("../exe/henni", __dir__)
    output, log, status = Open3.capture3(RbConfig.ruby, cli, "run", "--runner", "rspec",
                                       "--exclude", "generated/**/*.js", "--exclude", "bulky/node_modules",
                                       "lib/discount.rb", chdir: @source)
    report = JSON.parse(output)
    expect(status.exitstatus).to eq(1), log
    expect(report.dig("duration", "snapshot_seconds")).to be >= 0
    expect(report.dig("baseline", "suites", "rspec", "duration")).to include(
      "copy_seconds" => (be >= 0), "test_seconds" => (be >= 0)
    )
    expect(report.dig("mutations", 0, "suites", "rspec", "duration")).to include(
      "copy_seconds" => (be >= 0), "test_seconds" => (be >= 0)
    )
    expect(File).to exist(File.join(@source, "generated/deep/artifact.js"))
  end
end
