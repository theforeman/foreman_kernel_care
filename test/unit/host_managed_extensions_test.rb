require 'test_plugin_helper'

module ForemanKernelCare
  class HostManagedExtensionsTestBase < ActiveSupport::TestCase
  end

  class HostInstalledPackagesTest < HostManagedExtensionsTestBase
    def setup
      feature = RemoteExecutionFeature.register('kernel_version', 'Kernel version')
      template = FactoryBot.create(:job_template, name: 'Kernel versionl')
      template.sync_feature(feature.label)

      @host = FactoryBot.create(:host, :with_kernelcare)
      package_json = {:name => "kernel", :version => "1", :release => "1.el7", :arch => "x86_64", :epoch => "1",
                      :nvra => "kernel-1-1.el7.x86_64"}
      @host.import_package_profile([::Katello::Pulp::SimplePackage.new(package_json)])
      @nvra = 'kernel-1-1.el7.x86_64'
      @host.reload
    end

    def test_update_kernel_version
      version = '2'
      release = '2.el7'
      @host.update_kernel_version(version, release)
      kernel_package = @host.installed_packages.where(name: 'kernel').first

      assert_not_equal kernel_package.nvra, @nvra
      assert_equal kernel_package.version, version
      assert_equal kernel_package.release, release
    end
  end

  class HostTracerTest < HostManagedExtensionsTestBase
    def setup
      feature = RemoteExecutionFeature.register('update_kernel', 'Update Kernel')
      template = FactoryBot.create(:job_template, name: 'Update kernel')
      template.sync_feature(feature.label)

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
