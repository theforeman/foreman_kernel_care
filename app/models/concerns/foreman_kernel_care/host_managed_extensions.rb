module ForemanKernelCare
  module HostManagedExtensions
    def import_package_profile(simple_packages)
      ::JobInvocationComposer.for_feature(:kernel_version, self).trigger! if kernelcare?

      super(simple_packages)
    end

    def import_tracer_profile(tracer_profile)
      if kernelcare?
        new_tracer_profile = {}
        tracer_profile.each do |trace, attributes|
          if trace.to_s == 'kernel'
            ::JobInvocationComposer.for_feature(:update_kernel, self).trigger!
          else
            new_tracer_profile[trace] = attributes
          end
        end
        super(new_tracer_profile)
      else
        super(tracer_profile)
      end
    end

    def update_kernel_version(version, release, old_kernel_version)
      old_version, old_release = old_kernel_version.split('-')

      case operatingsystem.family
      when 'Redhat'
        packages = find_yum_kernel_packages(old_version, old_release)
        return if packages.empty?

        delete_yum_pkgs(packages)
        create_new_yum_kernel_packages(packages, version, release)
      when 'Debian'
        old_version = "#{old_version}-#{old_release}"
        new_version = "#{version}-#{release}"
        packages = find_deb_kernel_packages(old_version)
        return if packages.empty?

        create_new_deb_kernel_packages(packages, new_version, old_version)
      end
    end

    def kernelcare?
      !installed_packages.select { |package| package.name == 'kernelcare' }.empty? ||
        !installed_debs.select { |package| package.name == 'kernelcare' }.empty?
    end

    class ::Host::Managed::Jail < Safemode::Jail
      allow :installed_debs, :kernelcare?
    end

    protected

    def find_yum_kernel_packages(old_version, old_release)
      installed_packages.select do |p|
        p.name.include?('kernel') &&
          p.name != 'kernelcare' &&
          p.version == old_version &&
          old_release.include?(p.release)
      end
    end

    def delete_yum_pkgs(packages)
      delete_ids = packages.map(&:id)
      ::Katello::Util::Support.active_record_retry do
        table_name = host_installed_packages.table_name
        queries = []

        if delete_ids.any?
          queries << "DELETE FROM #{table_name} WHERE host_id=#{id} AND installed_package_id IN (#{delete_ids.join(', ')})"
        end

        queries.each do |query|
          ::ActiveRecord::Base.connection.execute(query)
        end
      end
    end

    def create_new_yum_kernel_packages(packages, version, release)
      new_kernels = packages.map do |p|
        ::Katello::SimplePackage.new({
          arch: p.arch,
          epoch: p.epoch,
          version: version,
          release: release,
          name: p.name
        })
      end
      found = import_package_profile_in_bulk(new_kernels)
      sync_yum_kernel_associations(found.map(&:id).uniq)
    end

    def sync_yum_kernel_associations(new_patched_kernel_ids)
      ::Katello::Util::Support.active_record_retry do
        table_name = host_installed_packages.table_name

        queries = []

        unless new_patched_kernel_ids.empty?
          inserts = new_patched_kernel_ids.map { |unit_id| "(#{unit_id.to_i}, #{id.to_i})" }
          queries << "INSERT INTO #{table_name} (installed_package_id, host_id) VALUES #{inserts.join(', ')}"
        end

        queries.each do |query|
          ::ActiveRecord::Base.connection.execute(query)
        end
      end
    end

    def find_deb_kernel_packages(old_version)
      installed_debs.select do |p|
        p.name.include?('linux') && p.version.include?(old_version)
      end
    end

    def create_new_deb_kernel_packages(packages, new_version, old_version)
      old_kernel_ids = packages.map(&:id)
      new_kernels = packages.map do |p|
        name = if p.name.include?(old_version)
                 p.name.sub(old_version, new_version)
               else
                 p.name
               end
        ::Katello::InstalledDeb.find_or_create_by(name: name, architecture: p.architecture, version: new_version)
      end
      return if new_kernels.empty? || old_kernel_ids.empty?

      sync_deb_kernel_associations(new_kernels.map(&:id), old_kernel_ids)
    end

    def sync_deb_kernel_associations(new_patched_kernel_ids, old_kernel_ids)
      new_installed_debs = installed_deb_ids.reject do |id|
        old_kernel_ids.include?(id)
      end
      self.installed_deb_ids = new_installed_debs.concat(new_patched_kernel_ids)
      save!
    end
  end
end
