# Uses `$evm.execute('create_provision_request', ..)` to create new VMs using the given information.
# 
# @param parsed_dialog_options    String (YAML) Parsed dialog options
# @param parsed_dialog_tags       String (YAML) Parsed dialog tags
# @param custom_vm_fields         Hash          Additional custom VM fields. See $evm.execute('create_provision_request')
# @param custom_additional_values Hash          Additional custom additional (ws) fields. See $evm.execute('create_provision_request')
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

def yaml_data(task, option)
  task.get_option(option).nil? ? nil : YAML.load(task.get_option(option))
end

# Creates provision requests based on the givin parameters.
#
# @param task                        ServiceTemplateProvisionTask Task used to create the service that will own the VMs created by these provision request(s)
# @param requester                   User                         User requesting the new VMs
# @param number_of_vms               Integer                      Number of VMs to provision
# @param provisioning_network_name_pattern String                 Provisioning network name pattern
# @param template_fields             Hash                         Hash describing the template to use.
#                                                                 Must contain :name and :guid fields.
# @param dialog_options              Hash                         User set options via dialog
# @param tags                        Hash                         Tags to set on the created VMs.
#                                                                 Default {}
# @param custom_vm_fields            Hash                         Custom vm_fields to use when creating the provsion request(s)
#                                                                 Default {}
# @param custom_additional_values    Hash                         Custom additional_values (ws_values) to use when creating the provsion request(s)
#                                                                 Default {}
# @param create_seperate_requests    Hash                         True to create seperate requests for each VM.
#                                                                 False to create one request that will create all of the requested VM(s)
#                                                                 Default true
#
# @return Array all of the created requests
def create_provision_requests(task, requester, number_of_vms,
                              provisioning_network_name_pattern,
                              template_fields, dialog_options,
                              tags = {}, custom_vm_fields = {}, custom_additional_values = {}, create_seperate_requests = true)
  $evm.log(:info, "START: create_provision_requests")                                          if @DEBUG
  $evm.log(:info, "number_of_vms                     => #{number_of_vms}")                     if @DEBUG
  $evm.log(:info, "provisioning_network_name_pattern => #{provisioning_network_name_pattern}") if @DEBUG
  $evm.log(:info, "template_fields                   => #{template_fields}")                   if @DEBUG
  $evm.log(:info, "dialog_options                    => #{dialog_options}")                    if @DEBUG
  $evm.log(:info, "tags                              => #{tags}")                              if @DEBUG
  $evm.log(:info, "custom_additional_values          => #{custom_additional_values}")          if @DEBUG
  $evm.log(:info, "custom_vm_fields                  => #{custom_vm_fields}")                  if @DEBUG
  $evm.log(:info, "create_seperate_requests          => #{create_seperate_requests}")          if @DEBUG
  
  # determine number of vms to create and
  # how many provisioning requests to create and
  # how many VMs per provisioning request
  if create_seperate_requests
    number_of_requests        = number_of_vms
    number_of_vms_per_request = 1
  else
    number_of_requests        = 1
    number_of_vms_per_request = number_of_vms
  end
  
  # === START: template_fields
  template_fields[:request_type] = 'template'
  # === END: template_fields

  # === START: vm_fields
  vm_fields = {}
  
  # determine if auto placement or not
  # NOTE: this used to be determined based on if the network was a cloud network or not,
  #       but now network is determined after placement, so need to cirlce back here and
  #       figure out new way to do cloud stuff.
  #       This current setting will likely break using this code with cloud right now
  vm_fields[:placement_auto] = true
  
  # TODO: used to set placement_availability_zone based on the selected network if cloud, but now network doesnt get set to later, so need way to figure out AZ, or do that automatically in determine placement

  vm_fields.merge!(custom_vm_fields)
  vm_fields.merge!(dialog_options)
  
  # override number of vms
  vm_fields[:number_of_vms] = number_of_vms_per_request
  
  # ensure option values are of correct type
  vm_fields[:vm_memory] = vm_fields[:vm_memory].to_s if !vm_fields[:vm_memory].nil?
  # === END: vm_fields

  # === START: requester
  requester = {
    :user_name        => requester.userid,     # need this otherwise requestor will always be 'admin'
    :owner_email      => requester.email,
    :owner_first_name => requester.first_name,
    :owner_last_name  => requester.last_name
  }
  # === END: requester

  # === START: additional_values (AKA: ws_values)
  additional_values = {
    :service_id                        => task.destination.id,
    :provisioning_network_name_pattern => provisioning_network_name_pattern
  }
  additional_values.merge!(custom_additional_values)
  additional_values.merge!(dialog_options)
  
  # override number of vms
  additional_values[:number_of_vms] = number_of_vms_per_request
  # === END: additional_values (AKA: ws_values)
  
  # Setup the parameters needed for request
  build_request = {
    :version           => '1.1',
    :template_fields   => template_fields,
    :vm_fields         => vm_fields,
    :requester         => requester,
    :tags              => tags,
    :additional_values => additional_values,
    :ems_custom_attrs  => {},
    :miq_custom_attrs  => {}
  }
  
  # Create the actual provision request(s)
  $evm.log(:info, "Execute '#{number_of_requests}' create_provision_requests for '#{number_of_vms_per_request}' VMs each: #{build_request}")
  requests = []
  number_of_requests.times do |count|
    requests << $evm.execute(
      'create_provision_request', 
      build_request[:version],
      build_request[:template_fields].stringify_keys,
      build_request[:vm_fields].stringify_keys, 
      build_request[:requester].stringify_keys,
      build_request[:tags].stringify_keys,
      build_request[:additional_values].stringify_keys,
      build_request[:ems_custom_attrs].stringify_keys,
      build_request[:miq_custom_attrs].stringify_keys)
  end
  $evm.log(:info, "requests => #{requests}") if @DEBUG
  
  $evm.log(:info, "END: create_provision_requests") if @DEBUG
  return requests
end

begin
  dump_current() if @DEBUG
  dump_root()    if @DEBUG
  
  # get options and tags
  $evm.log(:info, "$evm.root['vmdb_object_type'] => '#{$evm.root['vmdb_object_type']}'.") if @DEBUG
  case $evm.root['vmdb_object_type']
  when 'service_template_provision_task'
    task = $evm.root['service_template_provision_task']
    dump_object("service_template_provision_task", task) if @DEBUG

    dialog_options           = yaml_data(task, :parsed_dialog_options)
    dialog_options           = dialog_options[0] if !dialog_options[0].nil?
    dialog_tags              = yaml_data(task, :parsed_dialog_tags)
    custom_vm_fields         = task.get_option(:custom_vm_fields)
    custom_additional_values = task.get_option(:custom_additional_values)
  else
    error("Can not handle vmdb_object_type: #{$evm.root['vmdb_object_type']}")
  end
  $evm.log(:info, "dialog_options           => #{dialog_options}")           if @DEBUG
  $evm.log(:info, "dialog_tags              => #{dialog_tags}")              if @DEBUG
  $evm.log(:info, "custom_vm_fields         => #{custom_vm_fields}")         if @DEBUG
  $evm.log(:info, "custom_additional_values => #{custom_additional_values}") if @DEBUG
  
  # determine requestor
  user = $evm.root['user']
  dump_object("Current User", user) if @DEBUG
  
  # get the templates
  templates = YAML.load(dialog_options[:templates]) if dialog_options[:templates]
  error("Selected templates must be specified")     if templates.blank?
  $evm.log(:info, "templates => #{templates}")      if @DEBUG
  
  # get the number of VMs
  number_of_vms = dialog_options[:number_of_vms] || custom_vm_fields[:number_of_vms] || custom_additional_values[:number_of_vms] || 1
  $evm.log(:info, "umber_of_vms => #{number_of_vms}") if @DEBUG
  
  # Create new provision request(s) based on the number of requested VM(s) and the number of template(s)
  new_provision_requests = []
  base_vms_per_template = number_of_vms / templates.length
  templates.each_with_index do |template_fields, index|
    number_of_vms_for_this_template  = base_vms_per_template
    number_of_vms_for_this_template += 1 if index < number_of_vms % templates.length
    
    # set custom additional values
    destination_network_name    = dialog_options["location_#{index}_destination_network".to_sym]
    destination_network_gateway = dialog_options["location_#{index}_destination_network_gateway".to_sym]
    domain_name                 = dialog_options["location_#{index}_domain_name".to_sym]
    custom_additional_values[:destination_network]         = destination_network_name
    custom_additional_values[:destination_network_gateway] = destination_network_gateway
    custom_additional_values[:domain_name]                 = domain_name
    
    # handle cloud provider specific options
    cloud_flavor_id  = dialog_options["location_#{index}_cloud_flavor".to_sym]
    cloud_ssh_key_id = dialog_options["location_#{index}_cloud_ssh_key".to_sym]
    custom_vm_fields[:instance_type]         = cloud_flavor_id  if !cloud_flavor_id.blank?
    custom_vm_fields[:guest_access_key_pair] = cloud_ssh_key_id if !cloud_ssh_key_id.blank?
    # TODO: figure out these parameters
    #custom_vm_fields[:security_groups]       = ???
    
    # create provision requests
    provisioning_network_name_pattern = dialog_options["location_#{index}_provisioning_network".to_sym]
    new_provision_requests |= create_provision_requests(
                                task,
                                user,
                                number_of_vms_for_this_template,
                                provisioning_network_name_pattern,
                                template_fields,
                                dialog_options,
                                dialog_tags,
                                custom_vm_fields,
                                custom_additional_values)
  end
  
  # set requests on task so service task can wait for them to finish later in state machine
  provision_request_ids = task.get_option(:provision_request_ids) || {}
  provision_request_ids = provision_request_ids.values
  new_provision_requests.each do |provision_request|
    provision_request_ids << provision_request.id
  end
  provision_request_ids_hash = {}
  provision_request_ids.each_with_index { |id, index| provision_request_ids_hash[index] = id }
  task.set_option(:provision_request_ids, provision_request_ids_hash)
  $evm.log(:info, "task.get_option(:provision_request_ids) => #{task.get_option(:provision_request_ids)}") if @DEBUG
end
