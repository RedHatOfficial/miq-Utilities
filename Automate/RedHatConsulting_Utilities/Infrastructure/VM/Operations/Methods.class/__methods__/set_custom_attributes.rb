# Given a list of Custom Attributes, sets those Custom Attributes on the given VM.
#
# NOTE: Not meant to be overriden by implimentors.
#
# EXPECTED
#   EVM STATE || EVM CURRENT || EVM OBJECT || EVM ROOT
#     :vm                   - VM to set the Custom Attributes on
#     :vm_custom_attributes - Hash of Custom Attributes to value for the given VM
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

# Sets a custom attribute/value pair on a VM
#
# @param vm        VM to set the custom attribute on
# @param attribute Name of the attribute to set on the vm
# @param value     Value of the attribute to set on the vm
def set_vm_custom_attribute(vm, attribute, value)
  safe_attribute = attribute.gsub('[ :].*', '_')
  vm.custom_set(safe_attribute, value)
  $evm.log(:info, "Custom Attribute #{safe_attribute}=#{value} set on '#{vm.name}'") if @DEBUG
end

begin
  # get the VM
  if $evm.root['miq_provision']
    $evm.log(:info, "Get VM from $evm.root['miq_provision']") if @DEBUG
    vm = $evm.root['miq_provision'].vm
  else
    $evm.log(:info, "Get VM from paramater") if @DEBUG
    vm = get_param(:vm)
  end
  error("vm paramater not found") if vm.nil?
  $evm.log(:info, "vm=#{vm.name}") if @DEBUG
  
  # get the Custom Attributes to set
  vm_custom_attributes = get_param(:vm_custom_attributes)
  error("vm_custom_attributes paramater not found") if vm_custom_attributes.nil?
  $evm.log(:info, "vm_custom_attributes=#{vm_custom_attributes}") if @DEBUG
  
  # set the Custom Attributes on the VM
  vm_custom_attributes.each do |attribute, value|
    set_vm_custom_attribute(vm, attribute, value)
  end
end
