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

        # Add Global files for extending foreman-core components and routes
        register_global_js_file 'global'

        # Add permissions
        security_block :foreman_kernel_care do
          permission :view_foreman_kernel_care, { :'foreman_kernel_care/tracers' => [:index, :show] }
        end

        # Add a new role called 'Discovery' if it doesn't exist
        role 'ForemanKernelCare', [:view_foreman_kernel_care]

        # add menu entry
        sub_menu :top_menu, :plugin_template, icon: 'pficon pficon-process-automation', caption: N_('KernelCare'), after: :hosts_menu do
          menu :top_menu, :tracers, caption: N_('Tracers'), :url_hash => {:controller=> :'foreman_kernel_care/tracers', :action=>:index}
          #menu :top_menu, :new_action, caption: N_('New Action'), engine: ForemanKernelCare::Engine
        end

        # add dashboard widget
        widget 'foreman_kernel_care_widget', name: N_('KernelCare widget'), sizex: 4, sizey: 1
      end
    end

    # Include concerns in this config.to_prepare block
    config.to_prepare do

      begin
        Host::Managed.send(:include, ForemanKernelCare::HostExtensions)
        HostsHelper.send(:include, ForemanKernelCare::HostsHelperExtensions)
      rescue => e
        Rails.logger.warn "ForemanKernelCare: skipping engine hook (#{e})"
      end
    end

    rake_tasks do
      Rake::Task['db:seed'].enhance do
        ForemanKernelCare::Engine.load_seed
      end
    end

    initializer 'foreman_kernel_care.register_gettext', after: :load_config_initializers do |_app|
      locale_dir = File.join(File.expand_path('../../..', __FILE__), 'locale')
      locale_domain = 'foreman_kernel_care'
      Foreman::Gettext::Support.add_text_domain locale_domain, locale_dir
    end
  end
end
