require File.expand_path('../lib/foreman_kernel_care/version', __FILE__)

Gem::Specification.new do |s|
  s.name        = 'foreman_kernel_care'
  s.version     = ForemanKernelCare::VERSION
  s.license     = 'GPL-3.0'
  s.authors     = ['TODO: Your name']
  s.email       = ['TODO: Your email']
  s.homepage    = 'TODO'
  s.summary     = 'Plugin for KernelCare'
  # also update locale/gemspec.rb
  s.description = 'Plugin for KernelCare'

  s.files = Dir['{app,config,db,lib,locale,webpack}/**/*'] + ['LICENSE', 'Rakefile', 'README.md', 'package.json']
  s.test_files = Dir['test/**/*'] + Dir['webpack/**/__tests__/*.js']

  s.add_development_dependency 'rubocop'
  s.add_development_dependency 'rdoc'
end
