# frozen_string_literal: true

require 'foreman_remote_execution'

module ForemanKernelCare
  # Dependencies related with the remote execution plugin
  class Engine < ::Rails::Engine
    config.to_prepare do
      ForemanKernelCare::Engine.register_rex_feature
    end

    def self.register_rex_feature
      RemoteExecutionFeature.register(
        :update_kernel,
        N_('Run Update kernel'),
        :description => N_('Runs Update kernel')
      )

      RemoteExecutionFeature.register(
        :kernel_version,
        N_('Get patched kernel version'),
        :description => N_('Get patched kernel version')
      )
    end
  end
end
