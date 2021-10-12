# frozen_string_literal: true

require 'foreman_remote_execution'

module ForemanKernelCare
  # Dependencies related with the remote execution plugin
  class Engine < ::Rails::Engine
    def self.register_rex_feature
      RemoteExecutionFeature.register(
        :update_kernel,
        N_('Run Update kernel'),
        :description => N_('Runs Update kernel')
      )
    end
  end
end
