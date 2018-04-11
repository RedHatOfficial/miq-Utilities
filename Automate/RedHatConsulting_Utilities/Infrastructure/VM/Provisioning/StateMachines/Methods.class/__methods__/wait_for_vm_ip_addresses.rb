# Performs a VM refresh until VM IP addresses are available.
# If a destination_ip option is set then will wait for that IP to be available
#
# @param destination_ip Optional.
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
#   1. Inputs
#   2. Current
#   3. Object
#   4. Root
#   5. State
#
# @return Value for the given parameter or nil if none is found
def get_param(param)  
  # check if inputs has been set for given param
  param_value ||= $evm.inputs[param.to_sym]
  param_value ||= $evm.inputs[param.to_s]
  
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

# Function for getting the current VM and associated options based on the vmdb_object_type.
#
# Supported vmdb_object_types
#   * miq_provision
#   * vm
#   * automation_task
#
# @return vm,options
def get_vm_and_options()
  $evm.log(:info, "$evm.root['vmdb_object_type'] => '#{$evm.root['vmdb_object_type']}'.")
  case $evm.root['vmdb_object_type']
    when 'miq_provision'
      # get root object
      $evm.log(:info, "Get VM and dialog attributes from $evm.root['miq_provision']") if @DEBUG
      miq_provision = $evm.root['miq_provision']
      dump_object('miq_provision', miq_provision) if @DEBUG
      
      # get VM
      vm = miq_provision.vm
    
      # get options
      options = miq_provision.options
      #merge the ws_values, dialog, top level options into one list to make it easier to search
      options = options.merge(options[:ws_values]) if options[:ws_values]
      options = options.merge(options[:dialog])    if options[:dialog]
    when 'vm'
      # get root objet & VM
      $evm.log(:info, "Get VM from paramater and dialog attributes form $evm.root") if @DEBUG
      vm = get_param(:vm)
      dump_object('vm', vm) if @DEBUG
    
      # get options
      options = $evm.root.attributes
      #merge the ws_values, dialog, top level options into one list to make it easier to search
      options = options.merge(options[:ws_values]) if options[:ws_values]
      options = options.merge(options[:dialog])    if options[:dialog]
    when 'automation_task'
      # get root objet
      $evm.log(:info, "Get VM from paramater and dialog attributes form $evm.root") if @DEBUG
      automation_task = $evm.root['automation_task']
      dump_object('automation_task', automation_task) if @DEBUG
      
      # get VM
      vm  = get_param(:vm)
      
      # get options
      options = get_param(:options)
      options = JSON.load(options)     if options && options.class == String
      options = options.symbolize_keys if options
      #merge the ws_values, dialog, top level options into one list to make it easier to search
      options = options.merge(options[:ws_values]) if options[:ws_values]
      options = options.merge(options[:dialog])    if options[:dialog]
    else
      error("Can not handle vmdb_object_type: #{$evm.root['vmdb_object_type']}")
  end
  
  # standerdize the option keys
  options = options.symbolize_keys()
  
  $evm.log(:info, "vm      => #{vm}")      if @DEBUG
  $evm.log(:info, "options => #{options}") if @DEBUG
  return vm,options
end

begin
  # get VM and options
  vm,options = get_vm_and_options()
  error("vm parameter not found") if vm.blank?
  
  # check to see if there is an expected destination ip
  expected_ip = options[:destination_ip] || get_param(:destination_ip)
  
  # ensure VM IP addresses are set
  if vm.ipaddresses.nil? || vm.ipaddresses.empty?
    $evm.log(:info, "VM <#{vm.name}> IP addresses not detected yet, perform VM refresh and retry.") if @DEBUG
    vm.refresh
    automate_retry(30, 'Wait for VM <#{vm.name}> refresh to detect VM IP addresses')  
  elsif !expected_ip.blank? && !vm.ipaddresses.include?(expected_ip)
    $evm.log(:info, "VM <#{vm.name}> IP addresses detected but does not contain expected IP <#{expected_ip}>") if @DEBUG
    vm.refresh
    automate_retry(30, "Wait for VM <#{vm.name}> refresh to detect expected VM IP <#{expected_ip}>") 
  else
    $evm.log(:info, "vm.ipaddresses => #{vm.ipaddresses}, expected_ip => #{expected_ip}") if @DEBUG
    $evm.root['ae_result'] = 'ok'
  end
end
