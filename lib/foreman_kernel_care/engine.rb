require 'foreman_kernel_care/remote_execution'

module ForemanKernelCare
  class Engine < ::Rails::Engine
    isolate_namespace ForemanKernelCare
    engine_name 'foreman_kernel_care'

    config.autoload_paths += Dir["#{config.root}/app/controllers/concerns"]
    config.autoload_paths += Dir["#{config.root}/app/helpers/concerns"]
    config.autoload_paths += Dir["#{config.root}/app/models/concerns"]
    config.autoload_paths += Dir["#{config.root}/app/overrides"]

    # Add any db migrations
    initializer 'foreman_kernel_care.load_app_instance_data' do |app|
      ForemanKernelCare::Engine.paths['db/migrate'].existent.each do |path|
        app.config.paths['db/migrate'] << path
      end
    end

    initializer 'foreman_kernel_care.register_plugin', :before => :finisher_hook do |_app|
      Foreman::Plugin.register :foreman_kernel_care do
        requires_foreman '>= 2.4.0'

        # Add a new role called 'Discovery' if it doesn't exist
        role 'Foreman KernelCare', [:view_job_templates]
      end
    end

    # Include concerns in this config.to_prepare block
    config.to_prepare do

      begin
        Host::Managed.send(:include, ForemanKernelCare::HostExtensions)
        HostsHelper.send(:include, ForemanKernelCare::HostsHelperExtensions)
        Katello::Concerns::HostManagedExtensions.send(:prepend, ForemanKernelCare::HostManagedExtensions)
      rescue => e
        Rails.logger.warn "ForemanKernelCare: skipping engine hook (#{e})"
      end
    end

    rake_tasks do
      Rake::Task['db:seed'].enhance do
        ForemanKernelCare::Engine.load_seed
      end
    end
  end
end
