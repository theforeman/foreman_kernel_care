module ForemanKernelCare
  module HostManagedExtensions

    def import_package_profile(simple_packages)
      if kernelcare?
        composer = ::JobInvocationComposer.for_feature(:kernel_version, self)
        composer.triggering.mode = :future
        composer.trigger!
      end

      super(simple_packages)
    end

    def import_tracer_profile(tracer_profile)
      if kernelcare?
        new_tracer_profile = {}
        tracer_profile.each do |trace, attributes|
          if trace.to_s == 'kernel'
            composer = ::JobInvocationComposer.for_feature(:update_kernel, self)
            composer.triggering.mode = :future
            composer.trigger!
          else
            new_tracer_profile[trace] = attributes
          end
        end
        unless new_tracer_profile.empty?
          super(new_tracer_profile)
        end
      else
        super(tracer_profile)
      end
    end

    def update_kernel_version(version, release)
      packages = ::Katello::InstalledPackage.where('name LIKE ?', '%kernel%').where.not(name: 'kernelcare').to_a
      delete_ids = []
      simple_packages = packages.map do |p|
        delete_ids << p.id
        ::Katello::Pulp::SimplePackage.new({
                                             arch: p.arch,
                                             epoch: p.epoch,
                                             version: version,
                                             release: release,
                                             name: p.name
                                           })
      end
      found = import_package_profile_in_bulk(simple_packages)
      sync_kernel_associations(found.map(&:id).uniq, delete_ids)
    end

    def sync_kernel_associations(new_patched_kernel_ids, delete_ids)
      ::Katello::Util::Support.active_record_retry do
        table_name = host_installed_packages.table_name

        queries = []

        if delete_ids.any?
          queries << "DELETE FROM #{table_name} WHERE host_id=#{id} AND installed_package_id IN (#{delete_ids.join(', ')})"
        end

        unless new_patched_kernel_ids.empty?
          inserts = new_patched_kernel_ids.map { |unit_id| "(#{unit_id.to_i}, #{id.to_i})" }
          queries << "INSERT INTO #{table_name} (installed_package_id, host_id) VALUES #{inserts.join(', ')}"
        end

        queries.each do |query|
          ::ActiveRecord::Base.connection.execute(query)
        end
      end
    end

    protected

    def kernelcare?
      !installed_packages.select { |package| package.name == 'kernelcare' }.empty?
    end
  end
end
