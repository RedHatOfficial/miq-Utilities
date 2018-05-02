# Determine the valid cloud flavors for a specific selected destination provider for the given number of CPUs and memory.
#
# @param dialog_templates           String YAML list of selected destination templates including destination provider specified by :provider element
# @param destination_provider_index Int    Index in the destination templates list for the provider this dialog is for
# @param dialog_number_of_sockets   Int    Number of sockets
# @param dialog_cores_per_socket    Int    Number of cores per socket
# @dialog_dialog_vm_memory          Int    Amount of memmory in GB
#
@DEBUG = true

TEMPLATES_DIALOG_OPTION = 'dialog_templates'.freeze

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

# @param visible_and_required Boolean true if the dialog element is visible and required, false if hidden
# @param values               Hash    Values for the dialog element
def return_dialog_element(visible_and_required, values)
  # create dialog element
  dialog_field = $evm.object
  dialog_field['data_type'] = "string"
  dialog_field['visible']   = visible_and_required
  dialog_field['required']  = visible_and_required
  dialog_field['values']    = values
  $evm.log(:info, "dialog_field['values'] => #{dialog_field['values']}") if @DEBUG
  
  exit MIQ_OK
end

begin
  dump_root()    if @DEBUG
  dump_current() if @DEBUG
  selectable_flavors = {}
  
  # If there isn't a vmdb_object_type yet just exit. The method will be recalled with an vmdb_object_type
  destination_cloud_provider_enabled = !$evm.root['vmdb_object_type'].blank?
  $evm.log(:info, "$evm.root['vmdb_object_type'] => #{$evm.root['vmdb_object_type']}") if @DEBUG
  return_dialog_element(false, selectable_flavors) if !destination_cloud_provider_enabled
  
  # If there are not any selected destination templates then hide dialog element
  destination_templates_yaml          = get_param(TEMPLATES_DIALOG_OPTION)
  destination_cloud_provider_enabled &= destination_templates_yaml =~ /^---/
  $evm.log(:info, "destination_templates_yaml => #{destination_templates_yaml}") if @DEBUG
  return_dialog_element(false, selectable_flavors) if !destination_cloud_provider_enabled
  
  # get parameters
  destination_provider_index = get_param(:destination_provider_index)
  $evm.log(:info, "destination_provider_index => #{destination_provider_index}") if @DEBUG
  
  # determine if provier with given index is selected
  destination_templates = YAML.load(destination_templates_yaml)
  $evm.log(:info, "destination_templates  => #{destination_templates}") if @DEBUG
  destination_cloud_provider_enabled &= destination_templates.length > destination_provider_index
  return_dialog_element(false, selectable_flavors) if !destination_cloud_provider_enabled
  
  # determine if provider is a cloud provider
  destination_provider_name = destination_templates[destination_provider_index][:provider]
  destination_provider      = $evm.vmdb(:ems).find_by_name(destination_provider_name)
  $evm.log(:info, "destination_provider_name => #{destination_provider_name}") if @DEBUG
  $evm.log(:info, "destination_provider      => #{destination_provider}")      if @DEBUG
  destination_cloud_provider_enabled &= destination_provider.type.include?('::Cloud')
  return_dialog_element(false, selectable_flavors) if !destination_cloud_provider_enabled
  
  # determine and validate user specified cpu count
  number_of_sockets = get_param(:dialog_option_0_number_of_sockets) || get_param(:dialog_number_of_sockets)
  cores_per_socket  = get_param(:dialog_option_0_cores_per_socket)  || get_param(:dialog_cores_per_socket)
  if number_of_sockets.nil? && cores_per_socket.nil?
    return_dialog_element(true, { nil => "ERROR: Could not determine <number of sockets or cores per socket>."})
  end
  number_of_sockets ||= 1
  cores_per_socket  ||= 1
  number_of_sockets = number_of_sockets.to_i
  cores_per_socket  = cores_per_socket.to_i
  $evm.log(:info, "number_of_sockets => #{number_of_sockets}")
  $evm.log(:info, "cores_per_socket  => #{cores_per_socket}")
  
  # determine and validate user specified memory
  memory_mb = get_param(:dialog_option_0_vm_memory) || get_param(:dialog_vm_memory)
  $evm.log(:info, "memory_mb => #{memory_mb}")
  return_dialog_element(true, { nil => "ERROR: Could not determine <memmory in MB>."}) if memory_mb.nil?
  memory_mb = memory_mb.to_i
  
  # find matching flavors
  valid_flavors = destination_provider.flavors.select { |flavor| flavor.cpus                   == number_of_sockets}
                                              .select { |flavor| flavor.cpu_cores              == cores_per_socket }
                                              .select { |flavor| (flavor.memory / 1024 / 1024) == memory_mb }
  $evm.log(:info, "selectable_flavors => #{selectable_flavors}") if @DEBUG
  
  # error if no selecteable flavors
  if valid_flavors.empty?
    return_dialog_element(true, { nil => "ERROR: Could not find any Flavors for Cloud Provider <#{destination_provider_name}> " +
                                         "that match the selected number of sockets <#{number_of_sockets}>, " +
                                         "cores per socket <#{cores_per_socket}>, and Memory <#{memory_mb} (MB)>."})
  end
  selectable_flavors = Hash[ *valid_flavors.collect { |flavor| [flavor['id'], "#{flavor['Description']} (destination_provider_name)"] }.flatten ]
  return_dialog_element(destination_cloud_provider_enabled, selectable_flavors)
end
