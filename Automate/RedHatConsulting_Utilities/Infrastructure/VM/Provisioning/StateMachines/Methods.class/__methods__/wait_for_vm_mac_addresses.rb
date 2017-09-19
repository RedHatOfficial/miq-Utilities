# Performs a VM refresh until VM MAC addresses are available.
#
# EXPECTED
#   EVM STATE || EVM CURRENT || EVM OBJECT || EVM ROOT || $evm.root['miq_provision']
#     vm - VM the new LDAP entry is for
#
@DEBUG = false

# Log an error and exit.
#
# @param msg Message to error with
def error(msg)
  $evm.log(:error, msg)
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = msg.to_s
  exit MIQ_STOP
end

# Perform a method retry for the given reason
#
# @param seconds Number of seconds to wait before next retry
# @param reason  Reason for the retry
def automate_retry(seconds, reason)
  $evm.root['ae_result']         = 'retry'
  $evm.root['ae_retry_interval'] = "#{seconds.to_i}.seconds"
  $evm.root['ae_reason']         = reason

  $evm.log(:info, "Retrying #{@method} after #{seconds} seconds, because '#{reason}'") if @DEBUG
  exit MIQ_OK
end

# There are many ways to attempt to pass parameters in Automate.
# This function checks all of them in priorty order as well as checking for symbol or string.
#
# Order:
#   1. Current
#   2. Object
#   3. Root
#   4. State
#
# @return Value for the given parameter or nil if none is found
def get_param(param)  
  # else check if current has been set for given param
  param_value ||= $evm.current[param.to_sym]
  param_value ||= $evm.current[param.to_s]
 
  # else cehck if current has been set for given param
  param_value ||= $evm.object[param.to_sym]
  param_value ||= $evm.object[param.to_s]
  
  # else check if param on root has been set for given param
  param_value ||= $evm.root[param.to_sym]
  param_value ||= $evm.root[param.to_s]
  
  # check if state has been set for given param
  param_value ||= $evm.get_state_var(param.to_sym)
  param_value ||= $evm.get_state_var(param.to_s)

  $evm.log(:info, "{ '#{param}' => '#{param_value}' }") if @DEBUG
  return param_value
end

begin
  # Depending on the vmdb_object_type get the required information from different sources
  $evm.log(:info, "$evm.root['vmdb_object_type'] => '#{$evm.root['vmdb_object_type']}'.")
  case $evm.root['vmdb_object_type']
    when 'miq_provision'
      miq_provision = $evm.root['miq_provision']
      vm            = miq_provision.vm
    when 'vm'
      vm = get_param(:vm)
    else
      error("Can not handle vmdb_object_type: #{$evm.root['vmdb_object_type']}")
  end
  error("vm parameter not found") if vm.blank?
  
  # ensure VM MAC addresses are set
  if vm.mac_addresses.nil? || vm.mac_addresses.empty?
    $evm.log(:info, "VM MAC addresses not detected yet, perform VM refresh and retry") if @DEBUG
    vm.refresh
    automate_retry(30, 'Wait for VM refresh to detect VM MAC addresses')  
  else
    $evm.log(:info, "vm.mac_addresses => #{vm.mac_addresses}") if @DEBUG
    $evm.root['ae_result'] = 'ok'
  end
end
