require 'katello'
require 'foreman_tasks'
require 'foreman_kernel_care/remote_execution'

module ForemanKernelCare
  class Engine < ::Rails::Engine
    isolate_namespace ForemanKernelCare
    engine_name 'foreman_kernel_care'

    config.autoload_paths += Dir["#{config.root}/app/models/concerns"]
    config.autoload_paths += Dir["#{config.root}/app/services/concerns"]

    initializer 'foreman_kernel_care.register_plugin', :before => :finisher_hook do |_app|
      Foreman::Plugin.register :foreman_kernel_care do
        requires_foreman '>= 1.19.0'
        role 'Foreman KernelCare', [:view_job_templates]
      end
    end

    # make sure the plugin is initialized before katello loads the host extensions
    initializer 'foreman_kernel_care.load_kernelcare_override', :before => :finisher_hook, :after => ['katello.register_plugin', 'foreman_tasks.register_plugin'] do
      ::Katello::Concerns::HostManagedExtensions.prepend ForemanKernelCare::HostManagedExtensions
      ::Katello::Host::ProfilesUploader.prepend ForemanKernelCare::ProfilesUploader
      ::ForemanTasks::Api::TasksController.prepend ForemanKernelCare::ForemanTasks
    end

    rake_tasks do
      Rake::Task['db:seed'].enhance do
        ForemanKernelCare::Engine.load_seed
      end
    end
  end
end
