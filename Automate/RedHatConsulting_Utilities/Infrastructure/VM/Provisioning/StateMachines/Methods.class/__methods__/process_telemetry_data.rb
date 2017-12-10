#
#
@DEBUG = true

PROVISIONING_TELEMETRY_PREFIX = "Telemetry: Provisioning:"

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
    current_time_zone = Time.now.zone
    duration = seconds_to_time(end_time.in_time_zone(current_time_zone) - start_time.in_time_zone(current_time_zone))
  else
    duration = 'Unknown'
  end
  
  $evm.log(:info, "get_duration: END: { :duration => #{duration}, :start_time => #{start_time}, :end_time => #{:end_time} }") if @DEBUG
  return duration
end

# Set VM custom attribute with provisioning telemetry data
def set_provisioning_telemetry_custom_attribute(vm, description, value)
  vm.custom_set("#{PROVISIONING_TELEMETRY_PREFIX} #{description}", value)
end

begin
  # Get vm from miq_provision object
  prov = $evm.root['miq_provision']
  vm = prov.vm
  error("VM not found") if vm.nil?
  
  # determine how long different steps took
  now                                = Time.now
  duration_vm_queue                  = get_duration(prov.created_on,                                   :telemetry_on_entry_CustomizeRequest)
  duration_vm_provisioning           = get_duration(:telemetry_on_entry_CustomizeRequest,              now)
  duration_vm_clone                  = get_duration(:telemetry_on_entry_Provision,                     :telemetry_on_exit_CheckProvisioned)
  duration_wait_for_vm_mac_addresses = get_duration(:telemetry_on_entry_WaitForVMMACAddresses,         :telemetry_on_exit_WaitForVMMACAddresses)
  duration_start_vm                  = get_duration(:telemetry_on_entry_StartVM,                       :telemetry_on_exit_StartVM)
  duration_wait_for_vm_ip_addresses  = get_duration(:telemetry_on_entry_PostSatelliteBuildCompleted_1, :telemetry_on_exit_PostSatelliteBuildCompleted_1)
  
  set_provisioning_telemetry_custom_attribute(vm, 'Time: Request Created',               prov.created_on.in_time_zone(now.zone))
  set_provisioning_telemetry_custom_attribute(vm, 'Time: Request Completed',             now)
  set_provisioning_telemetry_custom_attribute(vm, 'Hour: Request Created',               prov.created_on.in_time_zone(now.zone).hour)
  set_provisioning_telemetry_custom_attribute(vm, 'Hour: Request Completed',             now.hour)
  set_provisioning_telemetry_custom_attribute(vm, 'Duration: VM Queue',                  duration_vm_queue)
  set_provisioning_telemetry_custom_attribute(vm, 'Duration: VM Provisioning',           duration_vm_provisioning)
  set_provisioning_telemetry_custom_attribute(vm, 'Duration: VM Clone',                  duration_vm_clone)
  set_provisioning_telemetry_custom_attribute(vm, 'Duration: Wait for VM MAC Addresses', duration_wait_for_vm_mac_addresses)
  set_provisioning_telemetry_custom_attribute(vm, 'Duration: Start VM',                  duration_start_vm)
  set_provisioning_telemetry_custom_attribute(vm, 'Duration: Wait for VM IP Addresses',  duration_wait_for_vm_ip_addresses)
end
