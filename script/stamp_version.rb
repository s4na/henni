# Invoked from the checkout of the main push that triggered the release workflow.
revision = ENV.fetch("GITHUB_SHA")
patch = Integer(ENV.fetch("GITHUB_RUN_NUMBER"), 10)
abort "Expected a full commit SHA and a positive run number" unless revision.match?(/\A[0-9a-f]{40}\z/) && patch.positive?

current, previous_revision = File.readlines("VERSION", chomp: true)
major, minor, previous_patch = current.match(/\A(\d+)\.(\d+)\.(\d+)\z/).captures
version = "#{major}.#{minor}.#{patch}"
exit if version == current && revision == previous_revision
abort "Patch number must advance from #{current}" unless patch > Integer(previous_patch, 10)

# Update both the path specification and its entry in CHECKSUMS, leaving the
# development bundle's cross-platform dependencies and checksums untouched.
lock = File.read("Gemfile.lock")
entry = /^( +)henni \(#{Regexp.escape(current)}\)$/
abort "Missing henni #{current} in Gemfile.lock" unless lock.match?(entry)
File.write("Gemfile.lock", lock.gsub(entry) { "#{$1}henni (#{version})" })
File.write("VERSION", "#{version}\n#{revision}\n")
