# coding: utf-8
lib = File.expand_path("../lib/", __FILE__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)
require "vf-snapshots/version"

Gem::Specification.new do |gem|
  gem.authors       = ["Jon Marshall Smith"]
  gem.email         = ["jon@jms-audioware.com"]
  gem.description   = %q{Make some current AWS snapshots}
  gem.summary       = %q{Make some current AWS snapshots}
  gem.homepage      = "http://github.com/vertfin/vf-snapshots"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = ["vf-snapshots"]
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "vf-snapshots"
  gem.require_paths = ["lib"]
  gem.version       = VfSnapshots::VERSION

  gem.add_runtime_dependency "aws-sdk"
  gem.add_runtime_dependency "thor"
  gem.add_runtime_dependency "rainbow"
  gem.add_runtime_dependency "pony"

end

