module ForemanKernelCare
  module HostManagedExtensions
    # Packages shipped by kernel errata that track the kernel's version-release.
    # Any one of these left behind keeps the whole erratum applicable, because
    # Katello matches an erratum if ANY of its packages upgrades an installed one.
    #
    # Note perf/python-perf/python3-perf/bpftool/libperf/rtla/rv do NOT contain
    # "kernel", so the previous name.include?('kernel') test could never reach them.
    #
    # This list spans EL7 through EL10 deliberately. Names differ by generation and
    # a miss is silent: python3-perf is EL8+, python-perf is EL7, and the -matched
    # variants only exist on EL10. Derive additions from the packages the errata
    # actually ship on every generation in the fleet, not from one cohort.
    KERNEL_FAMILY_PACKAGES = %w[
      kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra
      kernel-devel kernel-devel-matched kernel-headers kernel-abi-stablelists
      kernel-modules-extra-matched kernel-modules-partner
      kernel-debug kernel-debug-core kernel-debug-devel
      kernel-debug-modules kernel-debug-modules-core kernel-debug-modules-extra
      kernel-debug-devel-matched kernel-debug-modules-extra-matched
      kernel-tools kernel-tools-libs kernel-tools-libs-devel kernel-cross-headers
      kernel-uki-virt kernel-uki-virt-addons kernel-doc
      bpftool perf python-perf python3-perf libperf rtla rv
    ].freeze

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
        # Target the KernelCare-patched EVR, not the running kernel's, so subpackages
        # versioned against a different kernel generation are covered too.
        packages = find_yum_kernel_packages(version, release)
        return if packages.empty?

        delete_yum_pkgs(packages)
        create_new_yum_kernel_packages(packages, version, release)
        regenerate_kernelcare_applicability
      when 'Debian'
        old_version = "#{old_version}-#{old_release}"
        new_version = "#{version}-#{release}"
        packages = find_deb_kernel_packages(old_version)
        return if packages.empty?

        create_new_deb_kernel_packages(packages, new_version, old_version)
        regenerate_kernelcare_applicability
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

    # The NEWEST installed package for each kernel-family name, but only where that
    # newest is still older than the KernelCare-patched EVR. Taking newest-per-name
    # (rather than every matching row) means older kernels stay in the host's
    # inventory: Katello resolves applicability against the newest version per
    # package name, so leaving them costs nothing and keeps the profile honest.
    def find_yum_kernel_packages(new_version, new_release)
      newest = {}
      installed_packages.each do |p|
        next unless KERNEL_FAMILY_PACKAGES.include?(p.name)

        cur = newest[p.name]
        newest[p.name] = p if cur.nil? || installed_older?(cur, p)
      end
      newest.values.select { |p| rpm_evr_older?(p.version, p.release, new_version, new_release) }
    end

    # Epoch outranks version in rpm ordering, so picking the newest installed
    # build of a name has to consider it: on EL7, python-perf carries epoch 1.
    #
    # Used only between two installed packages. The comparison against the
    # KernelCare target above stays version-and-release only, deliberately: that
    # target comes from `kcarectl --uname` and carries no epoch at all. Treating
    # its absent epoch as 0 would make every epoch-bearing package look newer
    # than the target, so it would never be rewritten, which is the exact
    # opposite of what this code is for.
    def installed_older?(older, newer)
      eo = package_epoch(older)
      en = package_epoch(newer)
      return eo < en unless eo == en

      rpm_evr_older?(older.version, older.release, newer.version, newer.release)
    end

    def package_epoch(pkg)
      pkg.respond_to?(:epoch) ? pkg.epoch.to_i : 0
    end

    # The rewrite above is raw SQL, which bypasses the callbacks that would normally
    # schedule this, so the applicability index would otherwise stay frozen at the
    # host's last profile import.
    def regenerate_kernelcare_applicability
      ::ForemanTasks.async_task(
        ::Actions::Katello::Applicability::Hosts::BulkGenerate,
        :host_ids => [id]
      )
    rescue StandardError => e
      ::Foreman::Logging.exception('foreman_kernel_care: applicability regeneration failed', e)
    end

    # rpmvercmp, sufficient for kernel EVRs. Compares version, then release.
    def rpm_evr_older?(v1, r1, v2, r2)
      cmp = rpm_vercmp(v1.to_s, v2.to_s)
      cmp.zero? ? rpm_vercmp(r1.to_s, r2.to_s).negative? : cmp.negative?
    end

    def rpm_vercmp(a, b)
      return 0 if a == b

      x = a.scan(/\d+|[A-Za-z]+/)
      y = b.scan(/\d+|[A-Za-z]+/)
      x.zip(y).each do |p, q|
        return 1 if q.nil?
        next if p == q

        pn = p.match?(/\A\d+\z/)
        qn = q.match?(/\A\d+\z/)
        return pn ? 1 : -1 if pn != qn
        return pn ? (p.to_i <=> q.to_i) : (p <=> q)
      end
      x.length <=> y.length
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
