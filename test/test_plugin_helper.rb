# This calls the main test_helper in Foreman-core
require 'test_helper'

# Add plugin to FactoryBot's paths
rex_factories_path = "#{ForemanRemoteExecution::Engine.root}/test/factories"
plugin_factories_path = File.join(File.dirname(__FILE__), 'factories')
FactoryBot.definition_file_paths << rex_factories_path
FactoryBot.definition_file_paths << plugin_factories_path
FactoryBot.reload
