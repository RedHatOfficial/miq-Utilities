# Provisions new VM(s) to an existing Service using the origional provisioning parameters of that Service.
# Essentially this "scales up" an existing Service with additional VM(s).
#
# Intended/Tested to be run from a button attached to a Service.
#
# EXPECTED
#   EVM ROOT
#     service              - Service to provision new VM(s) to
#     dialog_number_of_vms - Number of VM(s) to provision and add to the service
#
@DEBUG = false

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

def error(msg)
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = msg
  $evm.log(:error, msg)
  exit MIQ_OK
end

IGNORED_VM_TASK_OPTIONS = ['schedule_time', 'provision', 'pass', 'vm_target_name', 'vm_target_hostname', 'vm_notes', 'dest_cluster', 'dest_storage', 'networks']

# Get the vm provsining customization configuration.
#
# @return VM provisining configuration
VM_PROVISIONING_CONFIG_URI = 'Infrastructure/VM/Provisioning/Configuration/default'
def get_vm_provisioning_config()
  provisioning_config = $evm.instantiate(VM_PROVISIONING_CONFIG_URI)
  error("VM Provisioning Configuration not found") if provisioning_config.nil?
  
  return provisioning_config
end

# Creates and executes a provision request for provisioning new VM(s) to an existing service using the origional provision values form that service.
# Essentially this "scales up" a serivce with like VM(s).
#
# @param task              Origional Service Template Provision Task used to create the Service the new VM(s) will be provisioned too
# @param tags              Hash of tags to apply to the newly provisoned VM(s)
# @param number_of_vms     Number of new VM(s) to provision to the existing service (added to ws_values)
# @param additional_values (aka: ws_values) Additional key/value paris to pass to the VM provisioning request
def create_provision_request_from_service_template_provision_task(task, tags = {}, number_of_vms, additional_values)
  user = $evm.root['user']
  dump_object("Current User", user) if @DEBUG
  
  origional_vm_task  = task.miq_request_tasks.first.miq_request_tasks.first
  source_vm_template = origional_vm_task.source
  dump_object('Source VM Tempalte', source_vm_template) if @DEBUG
  
  origional_vm_task_options = origional_vm_task.options
  $evm.log(:info, "Source origional_vm_task_options Options => #{origional_vm_task_options}") if @DEBUG
  source_miq_provision_request_template_options = task.miq_request_tasks.first.service_resource.resource.options
  $evm.log(:info, "Source miq_provision_request_template Options => #{source_miq_provision_request_template_options}") if @DEBUG
  
  # === START: template fields
  template_fields = {}
  template_fields[:name]         = source_vm_template.name
  template_fields[:guid]         = source_vm_template.guid
  template_fields[:request_type] = 'template'
  # === END: template fields
  
  # === START: ws_values (additional fields) munging
  
  # NOTE:
  #   This whole crazy hash merging is due to the problem that legacy code had set options directly on the miq_request_tasks for VMs in a new service
  #   and not on the service itself or the miq_provision_request_template for the service. Though not positive there is any way around that.
  ws_values = {}
  origional_vm_task_options.each do |key, value|
    # ignore certain keys
    next if IGNORED_VM_TASK_OPTIONS.include?(key.to_s)
    
    # if the key is not in the origional source template add it as additional values (ws_values)
    if !source_miq_provision_request_template_options.has_key?(key)
      ws_values[key] = origional_vm_task_options[key]
    end
  end
  $evm.log(:info, "ws_values from origional_vm_task_options: #{ws_values}") if @DEBUG
  
  ws_values.merge!(YAML.load(task.options[:parsed_dialog_options])[0])
  ws_values.merge!(additional_values)
  ws_values.merge!({:number_of_vms => number_of_vms})
  ws_values.each {|k,v| ws_values[k] = v.kind_of?(Array) ? v[0] : v }                            # change weird [1, "1"] type values to just the first value
  ws_values.delete_if {|k,v| v.nil? || (v.kind_of?(Array) && v.select{|a_v| !a_v.nil?}.empty?) } # remove nil values
  ws_values.each {|k,v| ws_values[k] = v.is_a?(Numeric) ? v.to_s : v}                            # convert all numbers to strings
  
  # add parent service id
  service = task.destination
  ws_values[:service_id] = service.id
  
  $evm.log(:info, "ws_values after munging: #{ws_values}") if @DEBUG
  # === END: ws_values (additional fields) munging
  
  # === START: vm_fields munging
  vm_fields = source_miq_provision_request_template_options.dup
  vm_fields.each {|k,v| vm_fields[k] = v.kind_of?(Array) ? v[0] : v }                            # change weird [1, "1"] type values to just the first value
  vm_fields.delete_if {|k,v| v.nil? || (v.kind_of?(Array) && v.select{|a_v| !a_v.nil?}.empty?) } # remove nil values
  vm_fields.each {|k,v| vm_fields[k] = v.is_a?(Numeric) ? v.to_s : v}                            # convert all numbers to strings
  
  # override vm_fields with ws_values
  vm_fields.merge!(ws_values)
  
  # delete fields that shoulnd't be passed to new request
  vm_fields.delete(:schedule_time)
  
  $evm.log(:info, "vm_fields after munging: #{vm_fields}") if @DEBUG
  # === END: vm_fields munging

  # Setup the parameters needed for request
  build_request = {}
  build_request[:version]          = '1.1'
  build_request[:template_fields]  = template_fields
  build_request[:vm_fields]        = vm_fields
  build_request[:requester]        = {
    'user_name'        => user.userid,     # need this otherwise requestor will always be 'admin'
    'owner_email'      => user.email,
    'owner_first_name' => user.first_name,
    'owner_last_name'  => user.last_name
  }
  build_request[:tags]             = tags
  build_request[:ws_values]        = ws_values
  build_request[:ems_custom_attrs] = {}
  build_request[:miq_custom_attrs] = {}

  #Create the actual provision request
  $evm.log(:info, "Execute create_provision_request: #{build_request}")
  $evm.execute(
    'create_provision_request', 
    build_request[:version],
    build_request[:template_fields].stringify_keys,
    build_request[:vm_fields].stringify_keys, 
    build_request[:requester].stringify_keys,
    build_request[:tags].stringify_keys,
    build_request[:ws_values].stringify_keys,
    build_request[:ems_custom_attrs].stringify_keys,
    build_request[:miq_custom_attrs].stringify_keys)
end

begin
  dump_root()    if @DEBUG
  dump_current() if @DEBUG

  case $evm.root['vmdb_object_type']
  when 'service'
    # add VM to service from Service
    $evm.log(:info, "Add VMs to existing service")
    service = $evm.root['service']
  else
    error("Unexpected vmdb_object_type: #{$evm.root['vmdb_object_type']}")
  end

  # Locate the Service Template Provision Task -- it holds our original build request
  $evm.log(:info, "Service ID => #{service.id}") if @DEBUG
  task = $evm.vmdb('service_template_provision_task').find_by_destination_id(service.id)
  $evm.log(:info, "Origional service_template_provision_task: #{task}") if @DEBUG
  dump_object('Origional service_template_provision_task', task)        if @DEBUG

  # get the number of VMs to add from the dialog, or use 1 if not specified by dialog
  dialog_number_of_vms = $evm.root["dialog_number_of_vms"].to_i
  number_of_vms = dialog_number_of_vms == 0 ? 1 : dialog_number_of_vms
  
  # get the VM name suffix counter length
  vm_provisioning_config        = get_vm_provisioning_config()
  vm_name_suffix_counter_length = vm_provisioning_config['vm_name_suffix_counter_length']
  $evm.log(:info, "vm_name_suffix_counter_length_counter_length => '#{vm_name_suffix_counter_length}'") if @DEBUG
  
  # create the provisioning request
  create_provision_request_from_service_template_provision_task(
    task,
    {}, 
    number_of_vms,
    {
      :vm_name_suffix_counter_length => vm_name_suffix_counter_length
    }
  )
end
