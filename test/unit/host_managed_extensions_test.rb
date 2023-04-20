require 'test_plugin_helper'

module ForemanKernelCare
  class HostManagedExtensionsTestBase < ActiveSupport::TestCase
  end

  class HostInstalledPackagesTest < HostManagedExtensionsTestBase
    def setup
      feature = RemoteExecutionFeature.register('kernel_version', 'Kernel version')
      template = FactoryBot.create(:job_template, name: 'Kernel versionl')
      template.sync_feature(feature.label)
    end

    def test_update_kernel_version
      host = FactoryBot.create(:host, :with_kernelcare,
        :operatingsystem => FactoryBot.create(:operatingsystem,
          :family => 'Redhat'))
      package_json = { :name => 'kernel', :version => '1',
                       :release => '1.el7', :arch => 'x86_64', :epoch => '1',
                       :nvra => 'kernel-1-1.el7.x86_64' }
      host.import_package_profile([::Katello::Pulp::SimplePackage.new(package_json)])
      nvra = 'kernel-1-1.el7.x86_64'
      host.reload
      version = '2'
      release = '2.el7'
      old_kernel_version = '1-1.el7.x86_64'
      host.update_kernel_version(version, release, old_kernel_version)
      kernel_package = host.installed_packages.where(name: 'kernel').first

      assert_not_equal kernel_package.nvra, nvra
      assert_equal kernel_package.version, version
      assert_equal kernel_package.release, release
    end

    def test_update_kernel_version_debian
      host = FactoryBot.create(:host, :debian_with_kernelcare,
        :operatingsystem => FactoryBot.create(:operatingsystem,
          :major => '10',
          :release_name => 'rn10',
          :family => 'Debian'))
      kernels = [
        { architecture: 'x86_64', version: '1-1', name: 'linux-image-generic' },
        { architecture: 'x86_64', version: '1-1', name: 'linux-headers-generic ' },
        { architecture: 'x86_64', version: '1-1', name: 'linux-generic' },
        { architecture: 'x86_64', version: '1-1', name: 'linux-signed-generic' },
        { architecture: 'x86_64', version: '1-1', name: 'linux-image-1-1-generic' }
      ]
      kernel_deb_ids = kernels.map do |kernel|
        ::Katello::InstalledDeb.find_or_create_by(name: kernel[:name],
                                                  architecture: kernel[:architecture],
                                                  version: kernel[:version]).id
      end
      kernelcare_id = host.installed_deb_ids.first
      installed_deb_ids = kernel_deb_ids << kernelcare_id
      host.installed_deb_ids = installed_deb_ids
      host.save!

      version = '2'
      release = '2'
      old_kernel_version = '1-1-generic'
      host.update_kernel_version(version, release, old_kernel_version)
      debian_kernel_packages = host.installed_debs.select do |p|
        p.name.include?('generic')
      end
      debian_kernel_packages.each do |p|
        assert_not_equal p.name, 'linux-image-1-1-generic'
        assert_equal p.version, "#{version}-#{release}"
      end
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
