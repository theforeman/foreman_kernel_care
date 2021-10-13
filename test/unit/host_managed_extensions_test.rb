require 'test_plugin_helper'

module ForemanKernelCare
  class HostManagedExtensionsTestBase < ActiveSupport::TestCase
    def setup
      template = FactoryBot.create(:job_template, name: 'Update kernel')
      template.sync_feature('update_kernel')
    end
  end

  class HostTracerTest < HostManagedExtensionsTestBase
    def setup
      super
      @tracer_json = {
        "kernel": {
          "type": 'static',
          "helper": 'You will have to reboot your computer'
        }
      }
    end

    def test_import_kerenl_trace_with_kernelcare
      host = FactoryBot.create(:host, :with_kernelcare)
      host.import_tracer_profile(@tracer_json)
      host.reload

      assert_empty host.host_traces.where(application: 'kernel')
      assert_equal 1, JobInvocation.count
      assert_equal 'Update kernel', JobInvocation.first.description
    end

    def test_import_kerenl_trace_without_kernelcare
      host = FactoryBot.create(:host)
      host.import_tracer_profile(@tracer_json)
      host.reload

      assert_equal 1, host.host_traces.count
      assert_equal 'kernel', host.host_traces.first.application
      assert_empty JobInvocation.all
    end
  end
end
