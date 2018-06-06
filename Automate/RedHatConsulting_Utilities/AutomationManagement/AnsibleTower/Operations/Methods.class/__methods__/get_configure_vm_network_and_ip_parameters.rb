# Gets/Sets the parameters for use with the configure vm network and ip ansible job.
#
# @see https://github.com/RedHatOfficial/ansible-cloud_utils/blob/master/playbooks/configure_vm_network_and_ip.yml
#
# @param destination_network
# @param destination_ip
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

# Get the network configuration for a given network
#
# @param network_name Name of the network to get the configuraiton for
# @return Hash Configuration information about the given network
#                network_purpose
#                network_address_space
#                network_gateway
#                network_nameservers
#                network_ddi_provider
@network_configurations         = {}
@missing_network_configurations = {}
NETWORK_CONFIGURATION_URI       = 'Infrastructure/Network/Configuration'.freeze
def get_network_configuration(network_name)
  if @network_configurations[network_name].blank? && @missing_network_configurations[network_name].blank?
    begin
      @network_configurations[network_name] = $evm.instantiate("#{NETWORK_CONFIGURATION_URI}/#{network_name}")
    rescue
      @missing_network_configurations[network_name] = "WARN: No network configuration exists"
      $evm.log(:warn, "No network configuration for Network <#{network_name}> exists")
    end
  end
  return @network_configurations[network_name]
end

begin
  dump_root()    if @DEBUG
  dump_current() if @DEBUG
  
  vm,options = get_vm_and_options()
  
  # get destination network information
  network_name          = options[:destination_network] || options[:dialog_destination_network] || get_param(:destination_network)
  network               = $evm.vmdb(:lan).find_by_name(network_name) if !network_name.blank?
  network_configuration = get_network_configuration(network_name)
  network_address_space = network_configuration['network_address_space']
  error("Option <network_name> must be provided")                                                          if network_name.blank?
  error("Could not find Network <#{network_name}>")                                                        if network.blank?
  error("Could not find Network configuration for Network <#{network_name}>")                              if network_configuration.blank?
  error("Network configuration <#{network_configuration}> must contain <network_address_space> parameter") if network_address_space.blank?
  $evm.log(:info, "network_name          => #{network_name}")          if @DEBUG
  $evm.log(:info, "network               => #{network}")               if @DEBUG
  $evm.log(:info, "network_configuration => #{network_configuration}") if @DEBUG
  $evm.log(:info, "network_address_space => #{network_address_space}") if @DEBUG

  # get other required options
  destination_ip = options[:destination_ip_address] || options[:dialog_destination_ip_address] || get_param(:destination_ip_address)
  error("One of <destination_ip_address, dialog_destination_ip_address> must be provided.") if destination_ip.blank?

  # determine network gateway
  destination_network_gateway = options[:destination_network_gateway] || options[:dialog_destination_network_gateway] || get_param(:destination_network_gateway)
  if destination_network_gateway.blank?
    destination_network_gateway = network_configuration['network_gateway']
  end
  $evm.log(:info, "destination_network_gateway => #{destination_network_gateway}") if @DEBUG
  error("One of <destination_network_gateway, dialog_destination_network_gateway> must be provided " +
        "or the Network configuration <#{network_configuration}> must contain <network_gateway> parameter.") if destination_network_gateway.blank?
  
  # build job parameters
  job_parameters = {
    :dialog_param_vm_network_ip4                => destination_ip,
    :dialog_param_vm_network_ip4_netmask_prefix => network_address_space.match(/[0-9\.]+\/([0-9]+)/)[1].to_i,
    :dialog_param_vm_network_gw4                => destination_network_gateway,
    :dialog_param_vm_network_dns4               => network_configuration['network_nameservers'].nil? ? nil : network_configuration['network_nameservers'].join(','),
    :dialog_param_virt_network                  => network_name
  }
  case vm.vendor
    when 'vmware'
      job_parameters[:dialog_param_vsphere_network_type] = network.switch.shared ? 'dvs' : 'standard'
      job_parameters[:dialog_param_vsphere_hostname]     = vm.ext_management_system.hostname
      job_parameters[:dialog_param_vsphere_datacenter]   = vm.datacenter.name
      job_parameters[:dialog_param_vsphere_username]     = vm.ext_management_system.authentication_userid
      job_parameters[:dialog_param_vsphere_password]     = vm.ext_management_system.authentication_password
      job_parameters[:dialog_param_vsphere_network_type] = network.switch.shared ? 'dvs' : 'standard'
    when 'redhat'
      job_parameters[:dialog_param_ovirt_url]      = vm.ext_management_system.hostname
      job_parameters[:dialog_param_ovirt_username] = vm.ext_management_system.authentication_userid
      job_parameters[:dialog_param_ovirt_password] = vm.ext_management_system.authentication_password
    else
      error("Unsported virtualization vendor <#{vm.vendor}> for configuring VM network and IP address")
  end
  
  # set required job parameters
  miq_provision = $evm.root['miq_provision']
  job_parameters.each do |k,v|
    $evm.object[k.to_s] = v
    $evm.root[k.to_s]   = v
    miq_provision.set_option(k.to_s,v) if miq_provision
  end
  job_parameters.each_with_index do |value, index|
    key = value[0].to_s.match(/dialog_param_(.*)/)[1]
    $evm.object["param#{index+1}"] = "#{key}=#{value[1]}"
  end
  
  $evm.log(:info, "Set Ansible Tower Job Parameters: #{job_parameters}")
  dump_root()    if @DEBUG
  dump_current() if @DEBUG
end
