# Attempts to aquire an IP address using the DDI provider for the given network.
#
# @param network_name_parameter_name String Name of the parameter that contains the network name to get an IP address for.
#
# @set aquired_ip_address String IP address aquired fomr the DDI provider for the given network.
#
@DEBUG = false

DDI_PROVIDERS_URI = 'Infrastructure/Network/DDIProviders'.freeze

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

# Notify and log a message.
#
# @param level   Symbol             Level of the notification and log message
# @param message String             Message to notify and log
# @param subject ActiveRecord::Base Subject of the notification
def notify(level, message, subject)
  $evm.create_notification(:level => level, :message => message, :subject => subject)
  log_level = case level
    when :warning
      :warn
    else
      level
  end
  $evm.log(log_level, message)
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
      @network_configurations[network_name] = $evm.instantiate("#{NETWORK_CONFIGURATION_URI}/#{escaped_network_name}")
    rescue
      @missing_network_configurations[network_name] = "WARN: No network configuration exists"
      $evm.log(:warn, "No network configuration for Network <#{network_name}> (escaped <#{escaped_network_name}>) exists")
    end
  end
  return @network_configurations[network_name]
end

begin
  vm,options = get_vm_and_options()
  
  network_name_parameter_name = get_param(:network_name_parameter_name)
  network_name                = get_param(network_name_parameter_name) || get_param("dialog_#{network_name_parameter_name}")
  
  if !network_name.blank?
    network_configuration       = get_network_configuration(network_name)
    $evm.log(:info, "network_name_parameter_name => #{network_name_parameter_name}") if @DEBUG
    $evm.log(:info, "network_name                => #{network_name}")                if @DEBUG
    $evm.log(:info, "network_configuration       => #{network_configuration}")       if @DEBUG

    # determine the DDI provider
    ddi_provider = network_configuration['network_ddi_provider']
    $evm.log(:info, "ddi_provider => #{ddi_provider}") if @DEBUG
  
    # instantiate instance to acquire IP
    begin
      $evm.log(:info, "Acquire IP address using DDI Provider <#{ddi_provider}>") if @DEBUG
    
      $evm.root['network_name'] = network_name
      $evm.instantiate("#{DDI_PROVIDERS_URI}/#{ddi_provider}#acquire_ip_address")
      acquired_ip_address = get_param(:acquired_ip_address)
    
      $evm.log(:info, "Acquired IP address <#{acquired_ip_address}> using DDI Provider <#{ddi_provider}>") if @DEBUG
    ensure
      success = $evm.root['ae_result'] == nil || $evm.root['ae_result'] == 'ok'
      reason  = $evm.root['ae_reason'] if !success
    
      # clean up root
      $evm.root['ae_result'] = 'ok'
      $evm.root['ae_reason'] = "Acquired IP address <#{acquired_ip_address}> for VM <#{vm.name}>"
    
      # clean up after call
      $evm.root['network_name']       = nil
      $evm.root['acquired_ip_address'] = nil
    end
    error("Error acquiring IP address using DDI Provider <#{ddi_provider}>: #{reason}") if !success
  else
    $evm.log(:warn, "No value for the expected network name parameter <#{network_name_parameter_name}> was given. Skipping aquiring IP address.")
  end
  
  # set the acquired IP
  $evm.object['acquired_ip_address'] = acquired_ip_address
end
