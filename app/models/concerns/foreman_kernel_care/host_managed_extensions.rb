module ForemanKernelCare
  module HostManagedExtensions
    def import_package_profile(simple_packages)
      if kernelcare?
        composer = ::JobInvocationComposer.for_feature(:kernel_version, self)
        composer.triggering.mode = :future
        composer.trigger!
      end

      found = import_package_profile_in_bulk(simple_packages)
      sync_package_associations(found.map(&:id).uniq)
    end

    def import_tracer_profile(tracer_profile)
      traces = []
      tracer_profile.each do |trace, attributes|
        next if attributes[:helper].blank?

        if trace.to_s == 'kernel' && kernelcare?
          composer = ::JobInvocationComposer.for_feature(:update_kernel, self)
          composer.triggering.mode = :future
          composer.trigger!

          next
        end

        traces << { host_id: id, application: trace, helper: attributes[:helper], app_type: attributes[:type] }
      end
      host_traces.delete_all
      Katello::HostTracer.import(traces, validate: false)
      update_trace_status
    end

    protected

    def kernelcare?
      !installed_packages.select { |package| package.name == 'kernelcare' }.empty?
    end
  end
end
