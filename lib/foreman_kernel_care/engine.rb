require 'foreman_kernel_care/remote_execution'

module ForemanKernelCare
  class Engine < ::Rails::Engine
    isolate_namespace ForemanKernelCare
    engine_name 'foreman_kernel_care'

    config.autoload_paths += Dir["#{config.root}/app/models/concerns"]

    initializer 'foreman_kernel_care.register_plugin', :before => :finisher_hook do |_app|
      Foreman::Plugin.register :foreman_kernel_care do
        requires_foreman '>= 1.19.0'

        # Add a new role called 'Discovery' if it doesn't exist
        role 'Foreman KernelCare', [:view_job_templates]
      end
    end

    # Include concerns in this config.to_prepare block
    config.to_prepare do
      Katello::Concerns::HostManagedExtensions.prepend ForemanKernelCare::HostManagedExtensions
      ForemanTasks::Api::TasksController.prepend ForemanKernelCare::ForemanTasks
    rescue StandardError => e
      Rails.logger.warn "ForemanKernelCare: skipping engine hook (#{e})"
    end

    rake_tasks do
      Rake::Task['db:seed'].enhance do
        ForemanKernelCare::Engine.load_seed
      end
    end
  end
end
