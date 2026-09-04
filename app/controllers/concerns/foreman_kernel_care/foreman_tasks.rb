module ForemanKernelCare
  module ForemanTasks
    def callback
      callbacks = params.key?(:callback) ? Array(params) : params[:callbacks]
      ids = callbacks.map { |payload| payload[:callback][:task_id] }
      foreman_tasks = ::ForemanTasks::Task.where(:id => ids)
      callbacks.each do |payload|
        # We need to call .to_unsafe_h to unwrap the hash from ActionController::Parameters
        callback = payload[:callback]
        foreman_task = foreman_tasks.find { |task| task.id == callback[:task_id] }
        next unless foreman_task&.action&.include?('Get patched kernel version')
        complete_output = ''
        result = payload[:data].to_unsafe_h['result']
        result.each { |x| complete_output += x['output'] }
        kernel, version, release = parse_kernel_versions(complete_output)
        next if kernel.nil?
        # This callback fires once per host sub-task, so the version parsed above
        # describes that one host. Applying it to every host in the invocation
        # writes one host's kernel NEVRA over all the others.
        host = host_for_kernel_version_task(foreman_task)
        next if host.nil?
        host.update_kernel_version(version, release, kernel)
      end

      super
    end

    private

    INSTALLED_PREFIX = 'Installed kernel version:'.freeze
    PATCHED_PREFIX = 'Patched kernel version:'.freeze

    # Selects the two lines by prefix rather than by position. kcarectl writes
    # "INFO: feature flags config override: ..." lines around its output; they go
    # to stderr today, so REX captures clean stdout and lines 0 and 1 happen to be
    # the right ones. If that ever changes, positional parsing takes a log line as
    # the kernel version and the nil release raises NoMethodError inside the
    # callback, which fails the whole batch rather than one host.
    #
    # Returns nil when either line is missing or malformed, so the caller skips
    # that host instead of writing a garbage version into its package rows.
    def parse_kernel_versions(complete_output)
      lines = complete_output.to_s.split(/\n/).map(&:strip)
      installed = lines.find { |line| line.start_with?(INSTALLED_PREFIX) }
      patched = lines.find { |line| line.start_with?(PATCHED_PREFIX) }
      return nil if installed.nil? || patched.nil?

      kernel = installed.sub(INSTALLED_PREFIX, '').strip
      version, release = patched.sub(PATCHED_PREFIX, '').strip.split('-', 2)
      return nil if kernel.empty? || version.nil? || version.empty? || release.nil? || release.empty?

      [kernel, version, release]
    end

    # RunHostJob calls action_subject(host, ...), so the per-host task carries its
    # host in the task input. TemplateInvocation#run_host_job_task_id is a second,
    # independent route to the same host, used when the input is unavailable.
    # Returning nil is the safe outcome: it skips this callback rather than
    # guessing at a host.
    def host_for_kernel_version_task(foreman_task)
      host_id = foreman_task.input&.dig('host', 'id') if foreman_task.respond_to?(:input)
      host_id ||= ::TemplateInvocation.find_by(:run_host_job_task_id => foreman_task.id)&.host_id
      return nil if host_id.nil?

      ::Host.find_by(:id => host_id)
    end
  end
end
