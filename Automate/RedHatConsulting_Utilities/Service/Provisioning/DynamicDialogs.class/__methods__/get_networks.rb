# Determine the destination networks for a specific selected destination provider.
#
# @param dialog_templates           String YAML list of selected destination templates including destination provider specified by :provider element
# @param destination_provider_index Int    Index in the destination templates list for the provider this dialog is for
# @param network_purpose            String Network purpose
#
@DEBUG = false

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

# Get all of the network configuration instances.
#
# @return Array of all of the network configuration instances enabled for dialogs
NETWORK_CONFIGURATION_URI = 'Infrastructure/Network/Configuration'.freeze
def get_network_configurations()
  network_instances = $evm.vmdb("MiqAeDomain").all.collect { |domain| $evm.instance_find("/#{domain.name}/#{NETWORK_CONFIGURATION_URI}/*") if domain.enabled}
  network_instances = Hash[*network_instances.collect{|h| h.to_a}.flatten.uniq]
  # remove network instances that should not be displayed based on network config
  network_instances.delete_if { |pattern, cfg| cfg['display_in_dialogs'].to_s == "false" }
  $evm.log(:info, "Network Instances to Display => #{network_instances}" ) if @DEBUG
  return network_instances
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
  selectable_networks = {}
  
  # If there isn't a vmdb_object_type yet just exit. The method will be recalled with an vmdb_object_type
  destination_provider_enabled = !$evm.root['vmdb_object_type'].blank?
  $evm.log(:info, "$evm.root['vmdb_object_type'] => #{$evm.root['vmdb_object_type']}") if @DEBUG
  return_dialog_element(false, selectable_networks) if !destination_provider_enabled
  
  # If there are not any selected destination templates then hide dialog element
  destination_templates_yaml          = get_param(TEMPLATES_DIALOG_OPTION)
  destination_provider_enabled &= destination_templates_yaml =~ /^---/
  $evm.log(:info, "destination_templates_yaml => #{destination_templates_yaml}") if @DEBUG
  return_dialog_element(false, selectable_networks) if !destination_provider_enabled
  
  # get parameters
  destination_provider_index = get_param(:destination_provider_index)
  network_purpose            = get_param(:network_purpose)
  required                   = get_param(:required)
  $evm.log(:info, "destination_provider_index => #{destination_provider_index}") if @DEBUG
  $evm.log(:info, "network_purpose            => #{network_purpose}")            if @DEBUG
  $evm.log(:info, "required                   => #{required}")                   if @DEBUG
  
  # determine if provier with given index is selected
  destination_templates = YAML.load(destination_templates_yaml)
  $evm.log(:info, "destination_templates  => #{destination_templates}") if @DEBUG
  destination_provider_enabled &= destination_templates.length > destination_provider_index
  return_dialog_element(false, selectable_networks) if !destination_provider_enabled
  
  # determine provider
  destination_provider_name = destination_templates[destination_provider_index][:provider]
  destination_provider      = $evm.vmdb(:ems).find_by_name(destination_provider_name)
  $evm.log(:info, "destination_provider_name => #{destination_provider_name}") if @DEBUG
  $evm.log(:info, "destination_provider      => #{destination_provider}")      if @DEBUG

  # collect host based networks
  all_host_networks = []
  destination_provider.hosts.each do |host|
    all_host_networks << host.lans.collect { |lan| lan.name }
  end
  $evm.log(:info, "all_host_networks => #{all_host_networks}") if @DEBUG
  # `inject(:|) does an `|` opertion on all elements of the array, thus doing a union
  union_of_host_networks = all_host_networks.inject(:|)
  $evm.log(:info, "union_of_host_networks => #{union_of_host_networks}") if @DEBUG
  
  # collect cloud based networks
  all_cloud_networks = []
  if destination_provider.respond_to?(:network_manager)
    all_cloud_networks << destination_provider.network_manager.cloud_subnets.collect { |cloud_subnet| cloud_subnet.name }
  end
  $evm.log(:info, "all_cloud_networks => #{all_cloud_networks}") if @DEBUG

  # determine the destination networks shared by all hosts on the selected destination provide
  all_networks  = []
  all_networks += union_of_host_networks if !union_of_host_networks.blank?
  all_networks += all_cloud_networks     if !all_cloud_networks.blank?
  $evm.log(:info, "all_networks => #{all_networks}") if @DEBUG
  
  # find networks that match the network configuration names
  network_configurations = get_network_configurations()
  $evm.log(:info, "network_configurations => #{network_configurations}") if @DEBUG
  network_configurations.each do |network_pattern, network_configuraiton|
    network_configurations[network_pattern][:networks] = all_networks.select { |network| network =~ /#{network_pattern}/ }
    $evm.log(:info, "Matching networks for #{network_pattern}: #{network_configurations[network_pattern][:networks]}") if @DEBUG
  end
  
  # determine the selecatable networks shared by all hosts that are also have network configuration with a network address space
  network_configurations.each do |network_name, network_configuration|
    if !network_configuration[:networks].empty? && network_configuration['network_purpose'].include?(network_purpose)
      selectable_networks[network_name] = "#{network_configuration['network_address_space']} (#{network_name}) (#{destination_provider_name}) (#{network_configuration[:networks]})"
    end
  end
  $evm.log(:info, "selectable_networks => #{selectable_networks}") if @DEBUG
  
  # if should be visible but can't find network configurations, show error
  # else prompt the user what this dialog element is for
  if required && destination_provider_enabled && selectable_networks.empty?
    selectable_networks[nil] = "ERROR: No Networks on Provider <#{destination_provider_name}> with configuration instances in <#{NETWORK_CONFIGURATION_URI}>."
  elsif destination_provider_enabled && selectable_networks.length > 1
    selectable_networks[nil] = "--- Select <#{destination_provider_name}> Destination Network"
  end
  
  # determine if the dialog element should be visible and required
  visible_and_required = destination_provider_enabled && (required || !selectable_networks.empty?)
  $evm.log(:info, "selectable_networks          => #{selectable_networks}")          if @DEBUG
  $evm.log(:info, "destination_provider_enabled => #{destination_provider_enabled}") if @DEBUG
  $evm.log(:info, "required                     => #{required}")                     if @DEBUG
  $evm.log(:info, "visible_and_required         => #{visible_and_required}")         if @DEBUG
  
  # return the dialog elemnt with the selectable networks
  return_dialog_element(visible_and_required, selectable_networks)
end
