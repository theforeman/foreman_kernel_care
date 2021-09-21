module ForemanKernelCare
  module HostManagedExtensions
    def import_tracer_profile(tracer_profile)
      traces = []
      tracer_profile.each do |trace, attributes|
        next if attributes[:helper].blank?

        next if trace == 'kernel' && kernelcare?

        traces << { host_id: self.id, application: trace, helper: attributes[:helper], app_type: attributes[:type] }
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
