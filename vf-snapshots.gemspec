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

  # gem.add_runtime_dependency "aws-sdk", '1.52.0'
  gem.add_runtime_dependency "aws-sdk", '2.11.133'
  gem.add_runtime_dependency "thor", '0.19.1'
  gem.add_runtime_dependency "rainbow", '2.0.0'
  gem.add_runtime_dependency "pony", '1.10'
  gem.add_runtime_dependency "byebug", '9.0.6'

end
