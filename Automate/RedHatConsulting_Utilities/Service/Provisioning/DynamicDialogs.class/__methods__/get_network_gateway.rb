# Determine the network gateway
#
# Parameters
#   destination_provider_index
#   network_purpose_tag_name
#
@DEBUG = false

NETWORK_GATEWAY_TAG_CATEGORY = 'network_gateway'.freeze

def dump_object(object_string, object)
  $evm.log("info", "Listing #{object_string} Attributes:") 
  object.attributes.sort.each { |k, v| $evm.log("info", "\t#{k}: #{v}") }
  $evm.log("info", "===========================================") 
end

def dump_current
  $evm.log("info", "Listing Current Object Attributes:") 
  $evm.current.attributes.sort.each { |k, v| $evm.log("info", "\t#{k}: #{v}") }
  $evm.log("info", "===========================================") 
end

def dump_root
  $evm.log("info", "Listing Root Object Attributes:") 
  $evm.root.attributes.sort.each { |k, v| $evm.log("info", "\t#{k}: #{v}") }
  $evm.log("info", "===========================================") 
end

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

begin
  dump_root()    if @DEBUG
  dump_current() if @DEBUG
  
  # If there isn't a vmdb_object_type yet just exit. The method will be recalled with an vmdb_object_type
  visible_and_required = !$evm.root['vmdb_object_type'].blank?
  $evm.log(:info, "$evm.root['vmdb_object_type'] => #{$evm.root['vmdb_object_type']}") if @DEBUG
  
  # determine the selected network to get the gateway for
  network_name = nil;
  if visible_and_required
    destination_provider_index = get_param(:destination_provider_index)
    network_purpose_tag_name   = get_param(:network_purpose_tag_name)
    $evm.log(:info, "destination_provider_index => #{destination_provider_index}") if @DEBUG
    $evm.log(:info, "network_purpose_tag_name   => #{network_purpose_tag_name}")   if @DEBUG
  
    network_name = get_param("dialog_provider_#{destination_provider_index}_#{network_purpose_tag_name}_network")
    $evm.log(:info, "network_name => #{network_name}") if @DEBUG
  end
  
  # if network has not yet been selected yet then not visible
  visible_and_required &= !network_name.blank?
  
  # determine the network gateway based on tag on the selected network
  network_gateway = nil
  if visible_and_required
    network = $evm.vmdb(:lan).find_by_name(network_name)
    $evm.log(:info, "network => #{network}") if @DEBUG
    
    network_gateway_tag_name = network.tags(NETWORK_GATEWAY_TAG_CATEGORY).first
    $evm.log(:info, "network_gateway_tag_name => #{network_gateway_tag_name}") if @DEBUG
    
    # if found gateway tag on the network
    # else error because not gateway tag found on the network
    if network_gateway_tag_name
      network_gateway_tag      = $evm.vmdb(:classification).find_by_name("#{NETWORK_GATEWAY_TAG_CATEGORY}/#{network_gateway_tag_name}")
      $evm.log(:info, "network_gateway_tag      => #{network_gateway_tag}") if @DEBUG
      network_gateway          = network_gateway_tag.description
      $evm.log(:info, "network_gateway          => #{network_gateway}")     if @DEBUG
    else
      network_gateway = "ERROR: No Tag <#{NETWORK_GATEWAY_TAG_CATEGORY}> found on selected Network <#{network_name}>"
    end
  end
  
  # create dialog element
  dialog_field = $evm.object
  dialog_field['data_type'] = "string"
  dialog_field['visible']   = visible_and_required
  dialog_field['required']  = visible_and_required
  dialog_field['value']     = network_gateway
  $evm.log(:info, "dialog_field['value'] => #{dialog_field['value']}") if @DEBUG
end
