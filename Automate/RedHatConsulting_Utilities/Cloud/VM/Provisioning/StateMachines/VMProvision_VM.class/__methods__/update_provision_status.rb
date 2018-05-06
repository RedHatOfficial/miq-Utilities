#
# Description: This method updates the provision status and sends an email with that update.
#
# Required inputs:
#   * status
#
# Optional Parameters:
#   * from_email_address
#   * additional_to_email_addresses
#
@DEBUG = false

VM_PROVISIONING_TELEMETRY_STATE_VAR_PREFIX = 'vm_provisioning_telemetry'
MIQ_PROVISION_UPDATE_EMAIL_URI             = 'Infrastructure/VM/Provisioning/Email/MiqProvision_Update'

# Log an error and exit.
#
# @param msg Message to error with
def error(msg)
  $evm.log(:error, msg)
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = msg.to_s
  exit MIQ_STOP
end

# Send an email about the status of the VM provisioning.
#
# @param prov            Provisioning task to send the update email about
# @param updated_message Updatd provisioning message
#
# @return true if success sending email, false otherwise.
def send_vm_provision_update_email(prov, updated_message)
  $evm.log(:info, "send_vm_provision_update_email: START: { prov => #{prov}, updated_message => #{updated_message} }") if @DEBUG
  
  # save current state of root
  current_root_prov      = $evm.root['prov']
  current_root_ae_result = $evm.root['ae_result']
  current_root_ae_reason = $evm.root['ae_reason']
  
  begin
    # instantiate the state machine to send a provision update email
    $evm.root['ae_result']                      = nil
    $evm.root['ae_reason']                      = nil
    $evm.root['prov']                           = prov
    $evm.root['vm_provision_update_message']    = updated_message
    $evm.root['vm_current_provision_ae_result'] = current_root_ae_result
    $evm.instantiate(MIQ_PROVISION_UPDATE_EMAIL_URI)
    success = true
  ensure
    success = $evm.root['ae_result'] == nil || $evm.root['ae_result'] == 'ok'
    success = $evm.root['ae_reason'] if !success
    
    # clean up root
    $evm.root['vm_provision_update_message'] = nil
    $evm.root['vm_current_provision_result'] = nil
    
    # reset root to previous state
    $evm.root['prov']      = current_root_prov
    $evm.root['ae_result'] = current_root_ae_result
    $evm.root['ae_reason'] = current_root_ae_reason
  end
  
  $evm.log(:info, "send_vm_provision_update_email: END: { prov => #{prov}, updated_message => #{updated_message} }") if @DEBUG
  return success
end

# Saves the current time as a state variable for processing later.
#
def save_telemetry()
  state_var_name = nil;
  step = $evm.root['ae_state']
  case $evm.root['ae_status_state']
    when 'on_entry'
      state_var_name      = "#{VM_PROVISIONING_TELEMETRY_STATE_VAR_PREFIX}_on_entry_#{step}"
      telematry_overwrite = false
    when 'on_exit'
      state_var_name      = "#{VM_PROVISIONING_TELEMETRY_STATE_VAR_PREFIX}_on_exit_#{step}"
      telematry_overwrite = true
    when 'on_error'
      state_var_name      = "#{VM_PROVISIONING_TELEMETRY_STATE_VAR_PREFIX}_on_error_#{step}"
      telematry_overwrite = true
  end
  state_var_name = state_var_name.to_sym
  
  if telematry_overwrite || !$evm.state_var_exist?(state_var_name)
    $evm.set_state_var(state_var_name, Time.now)
    $evm.log(:info, "Save Telemetry as State Var: { #{state_var_name} => #{$evm.get_state_var(state_var_name)}, :miq_request_id => #{prov.miq_request.id} }") if @DEBUG
  end
end

begin
  # get the provisioning task
  prov = $evm.root['miq_provision']
  $evm.log(:info, "Provision:<#{prov.id}> Request:<#{prov.miq_provision_request.id}> Type:<#{prov.type}>") if @DEBUG
  $evm.log(:info, "prov.attributes => {")                               if @DEBUG
  prov.attributes.sort.each { |k,v| $evm.log(:info, "\t#{k} => #{v}") } if @DEBUG
  $evm.log(:info, "}")                                                  if @DEBUG
  error("miq_provision object not provided") unless prov
  
  # get the status
  status = $evm.inputs['status']

  # Update Status Message
  updated_message  = "[#{$evm.root['miq_server'].name}] "
  updated_message += "VM [#{prov.get_option(:vm_target_name)}] "
  updated_message += "Step [#{$evm.root['ae_state']}] "
  updated_message += "Status [#{status}] "
  updated_message += "Message [#{prov.message}] "
  updated_message += "Current Retry Number [#{$evm.root['ae_state_retries']}]" if $evm.root['ae_result'] == 'retry'
  prov.miq_request.user_message = updated_message
  prov.message = status
  
  # save telemetry
  save_telemetry()
  
  # send email on error or if not send only on error
  if $evm.root['ae_result'] == "error" || !$evm.inputs['email_only_on_error']
    send_vm_provision_update_email(prov, updated_message)
  end
    
  # if there is an error then create a notificaiton and log message
  if $evm.root['ae_result'] == "error"
    $evm.create_notification(:level   => "error", \
                             :subject => prov.miq_request, \
                             :message => "VM Provision Error: #{updated_message}")

    $evm.log(:error, "VM Provision Error: #{updated_message}")
  end
end
