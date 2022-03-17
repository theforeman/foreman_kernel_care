module ForemanKernelCare
  module ForemanTasks
    def callback
      callbacks = params.key?(:callback) ? Array(params) : params[:callbacks]
      ids = callbacks.map { |payload| payload[:callback][:task_id] }
      foreman_tasks = ::ForemanTasks::Task.where(:id => ids)
      external_map = Hash[*foreman_tasks.pluck(:id, :external_id).flatten]
      callbacks.each do |payload|
        # We need to call .to_unsafe_h to unwrap the hash from ActionController::Parameters
        callback = payload[:callback]
        foreman_task = foreman_tasks.find { |task| task.id == callback[:task_id] }
        if foreman_task.action.include?('Get patched kernel version')
          version, release = payload[:data].to_unsafe_h['result'].first['output'].strip.split('-')
          job_invocation = ::JobInvocation.where(:task_id => foreman_task.parent_task_id).first
          job_invocation.targeting.hosts.each { |host| host.update_kernel_version(version, release) }
        end
        process_callback(external_map[callback[:task_id]], callback[:step_id].to_i, payload[:data].to_unsafe_h, :request_id => ::Logging.mdc['request'])
      end
      render :json => { :message => 'processing' }.to_json
    end
  end
end
