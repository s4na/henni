Gem::Specification.new do |s|
  s.name = "henni"
  s.version = "0.1.0"
  s.authors = ["s4na"]
  s.summary = "Mutation testing for Ruby comparison boundaries with Prism and RSpec"
  s.homepage = "https://github.com/s4na/henni"
  s.license = "MIT"
  s.required_ruby_version = ">= 3.4", "< 4.1"
  s.files = Dir["lib/**/*.rb", "exe/*", "README.md", "LICENSE"]
  s.bindir = "exe"
  s.executables = ["henni"]
  s.add_dependency "prism", "~> 2.1"
  s.add_dependency "rspec", "~> 3.13"
end
