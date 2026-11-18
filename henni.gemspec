Gem::Specification.new do |s|
  s.name = "henni"
  version, revision = File.readlines(File.join(__dir__, "VERSION"), chomp: true)
  s.version = version
  s.authors = ["s4na"]
  s.summary = "Mutation testing for Ruby comparison boundaries with Prism, RSpec and Minitest"
  s.homepage = "https://github.com/s4na/henni"
  s.metadata = { "source_revision" => revision, "source_code_uri" => "#{s.homepage}/tree/#{revision}" }
  s.license = "MIT"
  s.required_ruby_version = ">= 3.4", "< 4.1"
  s.files = Dir["lib/**/*.rb", "exe/*", "README.md", "LICENSE", "VERSION"]
  s.bindir = "exe"
  s.executables = ["henni"]
  s.add_dependency "prism", "~> 2.1"
end
