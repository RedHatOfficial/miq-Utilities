# Uses time data captured during the VM provisioning process to set custom attributes
# on the VM about the times taken to perform steps of the provisioning process.
#
# Parameters:
# 	ROOT
# 		* service_template_provision_task
#
@DEBUG = false

PROVISIONING_TELEMETRY_PREFIX = "Provisioning: Telemetry:"

# Converts duration of seconds to HH:MM:SS
#
# @param seconds Number of seconds passed
#
# @return duration converted to HH:MM:SS
def seconds_to_time(seconds)
  seconds = seconds.round
  return [seconds / 3600, seconds / 60 % 60, seconds % 60].map { |t| t.to_s.rjust(2,'0') }.join(':')
end

# Get the duration between two times.
#
# @return Duration in HH:MM:SS between to times, or Unknown, if any time is nil
def get_duration(start_time, end_time)
  $evm.log(:info, "get_duration: START: { :start_time => #{start_time}, :end_time => #{:end_time} }") if @DEBUG
  duration = 'Unknown'
  
  start_time = $evm.get_state_var(start_time) if start_time.class == Symbol
  end_time   = $evm.get_state_var(end_time)   if end_time.class   == Symbol
  
  if start_time && end_time
    duration = seconds_to_time(end_time.in_time_zone("UTC") - start_time.in_time_zone("UTC"))
  else
    duration = 'Unknown'
  end
  
  $evm.log(:info, "get_duration: END: { :duration => #{duration}, :start_time => #{start_time}, :end_time => #{:end_time} }") if @DEBUG
  return duration
end

# Set VM custom attribute with provisioning telemetry data
def set_provisioning_telemetry_custom_attribute(service, description, value)
  service.custom_set("#{PROVISIONING_TELEMETRY_PREFIX} #{description}", value)
end

begin
  # get the task
  task = $evm.root['service_template_provision_task']
  error("service_template_provision_task not found") if task.nil?
  $evm.log(:info, "task => #{task}") if @DEBUG
  
  # get the service
  service = task.destination
  error("Service not found") if service.nil?
  
  # determine how long different steps took
  now                                = Time.now
  duration_task_queue                = get_duration(task.created_on,                                    :service_provisioning_telemetry_on_entry_sequencer)
  duration_service_provisioning      = get_duration(:service_provisioning_telemetry_on_entry_sequencer, now)
  duration_initial_vms_provisioning  = get_duration(:service_provisioning_telemetry_on_entry_provision, :service_provisioning_telemetry_on_exit_checkprovisioned)
  
  set_provisioning_telemetry_custom_attribute(service, 'Time: Request Created',                task.created_on.localtime)
  set_provisioning_telemetry_custom_attribute(service, 'Time: Request Completed',              now)
  set_provisioning_telemetry_custom_attribute(service, 'Hour: Request Created',                task.created_on.localtime.hour)
  set_provisioning_telemetry_custom_attribute(service, 'Duration: Task Queue',                 duration_task_queue)
  set_provisioning_telemetry_custom_attribute(service, 'Duration: Total Service Provisioning', duration_service_provisioning)
  set_provisioning_telemetry_custom_attribute(service, 'Duration: Initial VMs Provisioning',   duration_initial_vms_provisioning)
end
