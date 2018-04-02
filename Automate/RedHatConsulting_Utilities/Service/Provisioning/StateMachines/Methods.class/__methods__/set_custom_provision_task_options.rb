# IMPLEMENTORS: intended to be overwritten.
#
# Sets additional dialog options on the given serivce.
#
@DEBUG = false

# IMPLEMENTORS: intended to be overwritten
#
# @param dialog_options Hash Dialog options set by user when creating the service.
#
# @return Hash of custom vm_fileds to set on any vm provisioning requests created for the service being created
def get_custom_vm_fields(dialog_options)
  custom_vm_fields = {
  }
  
  return custom_vm_fields
end

# IMPLEMENTORS: intended to be overwritten
#
# @param dialog_options Hash Dialog options set by user when creating the service.
#
# @return Hash of custom custom additional_values (ws_values) to set on any vm provisioning requests created for the service being created
def get_custom_additional_values(dialog_options)
  custom_additional_values = {
  }
  
  return custom_additional_values
end

# IMPLEMENTORS: do not modify
def dump_object(object_string, object)
  $evm.log("info", "Listing #{object_string} Attributes:") 
  object.attributes.sort.each { |k, v| $evm.log("info", "\t#{k}: #{v}") }
  $evm.log("info", "===========================================") 
end

# IMPLEMENTORS: do not modify
def dump_current
  $evm.log("info", "Listing Current Object Attributes:") 
  $evm.current.attributes.sort.each { |k, v| $evm.log("info", "\t#{k}: #{v}") }
  $evm.log("info", "===========================================") 
end

# IMPLEMENTORS: do not modify
def dump_root
  $evm.log("info", "Listing Root Object Attributes:") 
  $evm.root.attributes.sort.each { |k, v| $evm.log("info", "\t#{k}: #{v}") }
  $evm.log("info", "===========================================") 
end

# IMPLEMENTORS: do not modify
def error(msg)
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = msg
  $evm.log(:error, msg)
  exit MIQ_OK
end

# IMPLEMENTORS: do not modify
def yaml_data(task, option)
  task.get_option(option).nil? ? nil : YAML.load(task.get_option(option))
end

# IMPLEMENTORS: do not modify
begin
  dump_current() if @DEBUG
  dump_root()    if @DEBUG
  
  # get options and tags
  $evm.log(:info, "$evm.root['vmdb_object_type'] => '#{$evm.root['vmdb_object_type']}'.") if @DEBUG
  case $evm.root['vmdb_object_type']
  when 'service_template_provision_task'
    task = $evm.root['service_template_provision_task']
    dump_object("service_template_provision_task", task) if @DEBUG

    dialog_options = yaml_data(task, :parsed_dialog_options)
    dialog_options = dialog_options[0] if !dialog_options[0].nil?
  else
    error("Can not handle vmdb_object_type: #{$evm.root['vmdb_object_type']}")
  end
  $evm.log(:info, "dialog_options => #{dialog_options}") if @DEBUG
  
  # get the custom options
  custom_vm_fields         = get_custom_vm_fields(dialog_options)
  custom_additional_values = get_custom_additional_values(dialog_options)
  
  # set the custom options on the task
  task.set_option(:custom_vm_fields, custom_vm_fields)
  task.set_option(:custom_additional_values, custom_additional_values)
  $evm.log(:info, "Set :custom_vm_fields         => #{custom_vm_fields}")         if @DEBUG
  $evm.log(:info, "Set :custom_additional_values => #{custom_additional_values}") if @DEBUG
end
