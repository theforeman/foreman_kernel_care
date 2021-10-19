require File.expand_path('lib/foreman_kernel_care/version', __dir__)

Gem::Specification.new do |s|
  s.name        = 'foreman_kernel_care'
  s.version     = ForemanKernelCare::VERSION
  s.license     = 'GPL-3.0'
  s.authors     = ['Maxim Petukhov']
  s.email       = ['maxmol27@gmail.com']
  s.homepage    = 'https://github.com/maccelf/foreman_kernel_care'
  s.summary     = 'Plugin for KernelCare'
  s.description = 'This plugin removes kernel trace if KernelCare package is installed on host'

  s.files = Dir['{app,db,lib}/**/*'] + ['LICENSE', 'Rakefile', 'README.md']
  s.test_files = Dir['test/**/*']

  s.add_dependency 'katello', '>= 3.8.0'
  s.add_dependency 'foreman_remote_execution', '>= 1.5.6'

  s.add_development_dependency 'rdoc'
  s.add_development_dependency 'rubocop'
end
