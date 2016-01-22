# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ruboty/inc/version'

Gem::Specification.new do |spec|
  spec.name          = "ruboty-inc"
  spec.version       = Ruboty::Inc::VERSION
  spec.authors       = ["miyaz"]
  spec.email         = ["shi_miyazato_r@dreamarts.co.jp"]
  spec.summary       = %q{Show Incident Ticket Information}
  spec.description   = %q{Show Incident Ticket Information}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "ruboty"
  spec.add_development_dependency "bundler", "~> 1.10"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "ruboty-redis"
  spec.add_development_dependency "addressable"
end
