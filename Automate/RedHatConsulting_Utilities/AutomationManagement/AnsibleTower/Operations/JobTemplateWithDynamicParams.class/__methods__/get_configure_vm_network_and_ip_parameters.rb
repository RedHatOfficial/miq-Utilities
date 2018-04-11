# Gets/Sets the parameters for use with the configure vm network and ip ansible job.
#
# @see https://github.com/RedHatOfficial/ansible-cloud_utils/blob/master/playbooks/configure_vm_network_and_ip.yml
#
# @param destination_network
# @param destination_ip
# @param destination_network_gateway
@DEBUG = true

NETWORK_GATEWAY_TAG_CATEGORY = 'network_gateway'.freeze
ADDRESS_SPACE_TAG_CATEGORY   = 'network_address_space'.freeze

# Log an error and exit.
#
# @param msg Message to error with
def error(msg)
  $evm.log(:error, msg)
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = msg.to_s
  exit MIQ_STOP
end

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
  
  vm,options = get_vm_and_options()
  
  # get destination network information
  network_name                   = options[:destination_network] || options[:dialog_destination_network] || get_param(:destination_network)
  network                        = $evm.vmdb(:lan).find_by_name(network_name) if !network_name.blank?
  network_address_space_tag_name = network.tags(ADDRESS_SPACE_TAG_CATEGORY).first if !network.blank?
  network_address_space_tag      = $evm.vmdb(:classification).find_by_name("#{ADDRESS_SPACE_TAG_CATEGORY}/#{network_address_space_tag_name}") if !network_address_space_tag_name.blank?
  network_address_space          = network_address_space_tag.description if !network_address_space_tag.blank?
  $evm.log(:info, "network_name                   => #{network_name}")                   if @DEBUG
  $evm.log(:info, "network                        => #{network}")                        if @DEBUG
  $evm.log(:info, "network_address_space_tag_name => #{network_address_space_tag_name}") if @DEBUG
  $evm.log(:info, "network_address_space_tag      => #{network_address_space_tag}")      if @DEBUG
  $evm.log(:info, "network_address_space          => #{network_address_space}")          if @DEBUG

  # get other required options
  destination_ip              = options[:destination_ip]              || options[:dialog_destination_ip]              || get_param(:destination_ip)
  destination_network_gateway = options[:destination_network_gateway] || options[:dialog_destination_network_gateway] || get_param(:destination_network_gateway)

  # determine network gateway if not given
  if destination_network_gateway.blank?
    network_gateway_tag_name    = network.tags(NETWORK_GATEWAY_TAG_CATEGORY).first
    network_gateway_tag         = $evm.vmdb(:classification).find_by_name("#{NETWORK_GATEWAY_TAG_CATEGORY}/#{network_gateway_tag_name}") if !network_gateway_tag_name.blank?
    destination_network_gateway = network_gateway_tag.description if !network_gateway_tag.blank?
    $evm.log(:info, "network_gateway_tag_name    => #{network_gateway_tag_name}")    if @DEBUG
    $evm.log(:info, "network_gateway_tag         => #{network_gateway_tag}")         if @DEBUG
    $evm.log(:info, "destination_network_gateway => #{destination_network_gateway}") if @DEBUG
  end
  
  # build job parameters
  job_parameters = {
    :dialog_param_vm_network_ip4                => destination_ip,
    :dialog_param_vm_network_ip4_netmask_prefix => network_address_space.match(/[0-9\.]+\/([0-9]+)/)[1].to_i,
    :dialog_param_vm_network_gw4                => destination_network_gateway,
    :dialog_param_virt_network                  => network_name,
    :dialog_param_vsphere_network_type          => network.switch.shared ? 'dvs' : 'standard',
    :dialog_param_vsphere_hostname              => vm.ext_management_system.hostname,
    :dialog_param_vsphere_datacenter            => vm.datacenter.name,
    :dialog_param_vsphere_username              => vm.ext_management_system.authentication_userid,
    :dialog_param_vsphere_password              => vm.ext_management_system.authentication_password
  }
  
  # set required job parameters
  job_parameters.each { |k,v| $evm.object[k.to_s] = v }
  $evm.log(:info, "Set Ansible Tower Job Parameters: #{job_parameters}")
end
