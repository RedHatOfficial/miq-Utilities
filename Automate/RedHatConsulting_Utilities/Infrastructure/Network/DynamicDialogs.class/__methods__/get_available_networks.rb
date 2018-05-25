# Get the networks available to a given object.
#
# Suported Objects:
#  * vm
#
# @param network_purpose String Network purpose
@DEBUG = false

ADDRESS_SPACE_TAG_CATEGORY   = 'network_address_space'.freeze
DESTINATION_LAN_TAG_NAME     = 'destination'.freeze

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
      escaped_network_name                  = network_name.gsub(/[^a-zA-Z0-9_\.\-]/, '_')
      $evm.log(:info, "escaped_network_name => #{escaped_network_name}") if @DEBUG
      network_configuration                 = $evm.instantiate("#{NETWORK_CONFIGURATION_URI}/#{escaped_network_name}")
      
      if !network_configuration.blank? && !network_configuration['network_address_space'].blank?
        @network_configurations[network_name] = network_configuration
      else
        @missing_network_configurations[network_name] = "WARN: No network configuration exists"
        $evm.log(:warn, "No network configuration for Network <#{network_name}> (escaped <#{escaped_network_name}>) exists")
      end
    rescue
      @missing_network_configurations[network_name] = "WARN: No network configuration exists"
      $evm.log(:warn, "No network configuration for Network <#{network_name}> (escaped <#{escaped_network_name}>) exists")
    end
  end
  return @network_configurations[network_name]
end

begin
  vm,options      = get_vm_and_options()
  network_purpose = get_param(:network_purpose)
  
  # determine the destination networks shared by all hosts on the selected destination provider
  all_host_destination_networks = []
  destination_provider = vm.ext_management_system
  $evm.log(:info, "destination_provider => #{destination_provider}")      if @DEBUG
  destination_provider.hosts.each do |host|
    # find all the host destination networks
    host_destination_lans = []
    host.lans.each do |lan|
      network_configuraiton = get_network_configuration(lan.name)
      $evm.log(:info, "network_configuraiton['network_purpose'] => #{network_configuraiton.blank? ? nil : network_configuraiton['network_purpose']}") if @DEBUG
      host_destination_lans << lan if !network_configuraiton.blank? && (network_configuraiton['network_purpose'].include?(network_purpose))
    end

    all_host_destination_networks << host_destination_lans.collect { |lan| lan.name }
  end
  $evm.log(:info, "all_host_destination_networks => #{all_host_destination_networks}") if @DEBUG
  
  # `inject(:&) does an `&` opertion on all elements of the array, thus doing an intersection
  intersection_of_host_destination_lans = all_host_destination_networks.inject(:&)
  $evm.log(:info, "intersection_of_host_destination_lans => #{intersection_of_host_destination_lans}") if @DEBUG
  
  # determine the selecatable desintation networks shared by all hosts that are also tagged with a network address space
  selectable_networks = {}
  intersection_of_host_destination_lans.each do |network_name|
    network               = $evm.vmdb(:lan).find_by_name(network_name)
    network_configuration = get_network_configuration(network.name)
    if !network_configuration['network_address_space'].blank?
      selectable_networks[network_name] = "#{network_configuration['network_address_space']} (#{network_name}) (#{destination_provider.name})"
    end
  end
  $evm.log(:info, "selectable_networks => #{selectable_networks}") if @DEBUG
  
  selectable_networks[nil] = "--- Select <#{destination_provider.name}> Destination Network"
  
  # create dialog element
  dialog_field = $evm.object
  dialog_field['data_type'] = "string"
  dialog_field['visible']   = true
  dialog_field['required']  = true
  dialog_field['values']    = selectable_networks
  $evm.log(:info, "dialog_field['values'] => #{dialog_field['values']}") if @DEBUG
end
