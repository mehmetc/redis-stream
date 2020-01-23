
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "redis/stream/version"

Gem::Specification.new do |spec|
  spec.name          = "redis-stream"
  spec.version       = Redis::Stream::VERSION
  spec.authors       = ["Mehmet Celik"]
  spec.email         = ["mehmet@celik.be"]

  spec.summary       = %q{Sugar coating Redis Streams }
  spec.description   = %q{Simple stream library using Redis Streams}
  spec.homepage      = "https://github.com/mehmetc/redis-stream"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
#    spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

    spec.metadata["homepage_uri"] = spec.homepage
    spec.metadata["source_code_uri"] = "https://github.com/mehmetc/redis-stream"
    spec.metadata["changelog_uri"] = "https://github.com/mehmetc/redis-stream"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_dependency "redis", "4.1.3"
  spec.add_dependency "moneta", "~> 1.2"
  spec.add_dependency "multi_json", "~> 1.14"
end
