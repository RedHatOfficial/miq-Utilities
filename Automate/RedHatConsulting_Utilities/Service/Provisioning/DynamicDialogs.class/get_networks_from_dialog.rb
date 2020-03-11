# Determine the destination networks for a specific selected network providers dialog.
#
#
# @param destination_provider_index Int    Index in the destination templates list for the provider this dialog is for
# @param network_purpose            String Network purpose [destination_network|provisioning_network]

#
# Description: Return a Dialog with the same network info for destiantion network as 
# what was configured for the provisioning network, or vice versa
#

@DEBUG = false


require 'yaml'

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


# @param visible_and_required Boolean true if the dialog element is visible and required, false if hidden
# @param values               Hash    Values for the dialog element
def return_dialog_element(visible,required, values)
  # create dialog element
  dialog_field = $evm.object
  dialog_field['data_type'] = "string"
  dialog_field['visible']   = visible
  dialog_field['required']  = required
  dialog_field['values']    = values
  $evm.log(:info, "dialog_field['values'] => #{dialog_field['values']}") if @DEBUG
  
  exit MIQ_OK
end

begin

  # get parameters
  destination_provider_index = get_param(:destination_provider_index)
  network_purpose            = get_param(:network_purpose)
  required                   = get_param(:required)
  values                     = {}
  $evm.log(:info, "destination_provider_index => #{destination_provider_index}") if @DEBUG
  $evm.log(:info, "network_purpose            => #{network_purpose}")            if @DEBUG
  $evm.log(:info, "required                   => #{required}")                   if @DEBUG


  case network_purpose
    when 'provisioning'
    dialog_source_name = 'destination_network'
    when 'destination'
    dialog_source_name = 'provisioning_network'
    else
    dialog_source_name = 'unknown'
  end

  dialog_source = "dialog_location_#{destination_provider_index.to_s}_#{dialog_source_name}"

  source_network = $evm.root[dialog_source]
  
  # Only return values if a source_network is selected
  values = {source_network => source_network} if !source_network.blank?

  return_dialog_element(false,true,values)
  

end


