require 'rake/testtask'

# Tests
namespace :test do
  desc 'Test ForemanKernelCare'
  Rake::TestTask.new(:foreman_kernel_care) do |t|
    test_dir = File.expand_path('../../test', __dir__)
    t.libs << 'test'
    t.libs << test_dir
    t.pattern = "#{test_dir}/**/*_test.rb"
    t.verbose = true
    t.warning = false
  end
end

namespace :foreman_kernel_care do
  task rubocop: :environment do
    begin
      require 'rubocop/rake_task'
      RuboCop::RakeTask.new(:rubocop_foreman_kernel_care) do |task|
        task.patterns = ["#{ForemanKernelCare::Engine.root}/app/**/*.rb",
                         "#{ForemanKernelCare::Engine.root}/lib/**/*.rb",
                         "#{ForemanKernelCare::Engine.root}/test/**/*.rb"]
      end
    rescue StandardError
      puts 'Rubocop not loaded.'
    end

    Rake::Task['rubocop_foreman_kernel_care'].invoke
  end
end

Rake::Task[:test].enhance ['test:foreman_kernel_care']

load 'tasks/jenkins.rake'
if Rake::Task.task_defined?(:'jenkins:unit')
  Rake::Task['jenkins:unit'].enhance ['test:foreman_kernel_care', 'foreman_kernel_care:rubocop']
end
