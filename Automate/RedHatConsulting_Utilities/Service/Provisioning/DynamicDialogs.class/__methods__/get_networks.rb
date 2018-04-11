# Determine the destination networks for a specific selected destination provider.
#
# Parameters
#   dialog_templates           YAML list of selected destination templates including destination provider specified by :provider element
#   destination_provider_index Index in the destination templates list for the provider this dialog is for
#   network_purpose_tag_name   Name of the Network Purpose Tag Category Tag that the networks should be tagged with
#
@DEBUG = false

ADDRESS_SPACE_TAG_CATEGORY   = 'network_address_space'.freeze
TEMPLATES_DIALOG_OPTION      = 'dialog_templates'.freeze
NETWORK_PURPOSE_TAG_CATEGORY = 'network_purpose'.freeze
DESTINATION_LAN_TAG_NAME     = 'destination'.freeze

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

begin
  dump_root()    if @DEBUG
  dump_current() if @DEBUG
  
  # If there isn't a vmdb_object_type yet just exit. The method will be recalled with an vmdb_object_type
  visible_and_required = !$evm.root['vmdb_object_type'].blank?
  $evm.log(:info, "$evm.root['vmdb_object_type'] => #{$evm.root['vmdb_object_type']}") if @DEBUG
  
  # If there are not any selected destination templates then hide dialog element
  destination_templates_yaml = get_param(TEMPLATES_DIALOG_OPTION)
  visible_and_required &= destination_templates_yaml =~ /^---/
  $evm.log(:info, "destination_templates_yaml => #{destination_templates_yaml}") if @DEBUG
  
  # get parameters
  if visible_and_required
    destination_templates      = YAML.load(destination_templates_yaml)
    destination_provider_index = get_param(:destination_provider_index)
    network_purpose_tag_name   = get_param(:network_purpose_tag_name)
    
    $evm.log(:info, "destination_templates      => #{destination_templates}")      if @DEBUG
    $evm.log(:info, "destination_provider_index => #{destination_provider_index}") if @DEBUG
    $evm.log(:info, "network_purpose_tag_name   => #{network_purpose_tag_name}")   if @DEBUG
    
    # ensure there are more destination templates/providers then this destination network dialog is for
    visible_and_required &= destination_templates.length > destination_provider_index
  end
  
  # determine the destination networks shared by all hosts on the selected destination provider
  all_host_destination_networks = []
  destination_provider_name     = nil
  if visible_and_required
    destination_provider_name = destination_templates[destination_provider_index][:provider]
    destination_provider      = $evm.vmdb(:ems).find_by_name(destination_provider_name)
    
    $evm.log(:info, "destination_provider_name => #{destination_provider_name}") if @DEBUG
    $evm.log(:info, "destination_provider      => #{destination_provider}")      if @DEBUG

    destination_provider.hosts.each do |host|
          
      # find all the host destination networks
      host_destination_lans = []
      host.lans.each do |lan|
        host_destination_lans << lan if lan.tagged_with?(NETWORK_PURPOSE_TAG_CATEGORY, network_purpose_tag_name)
      end

      all_host_destination_networks << host_destination_lans.collect { |lan| lan.name }
    end
    $evm.log(:info, "all_host_destination_networks => #{all_host_destination_networks}") if @DEBUG

    # ensure there is a destination network that is tagged on all of the hosts on the provider 
    # `inject(:&) does an `&` opertion on all elements of the array, thus doing an intersection
    intersection_of_host_destination_lans = all_host_destination_networks.inject(:&)
    $evm.log(:info, "intersection_of_host_destination_lans => #{intersection_of_host_destination_lans}") if @DEBUG
  end
  
  # determine the selecatable desintation networks shared by all hosts that are also tagged with a network address space
  selectable_networks = {}
  if visible_and_required
    intersection_of_host_destination_lans.each do |network_name|
      network = $evm.vmdb(:lan).find_by_name(network_name)
      unless network.tags(ADDRESS_SPACE_TAG_CATEGORY).blank?
        network_address_space_tag_name = network.tags(ADDRESS_SPACE_TAG_CATEGORY).first
        network_address_space_tag      = $evm.vmdb(:classification).find_by_name("#{ADDRESS_SPACE_TAG_CATEGORY}/#{network_address_space_tag_name}")
        selectable_networks[network_name] = "#{network_address_space_tag.description} (#{network_name}) (#{destination_provider_name})"
      end
    end
    $evm.log(:info, "selectable_networks => #{selectable_networks}") if @DEBUG
  end
  
  # if should be visible but can't find destination networks, show error
  # else prompt the user what this dialog element is for
  if visible_and_required && selectable_networks.empty?
    destination_tag            = $evm.vmdb(:classification).find_by_name("#{NETWORK_PURPOSE_TAG_CATEGORY}/#{network_purpose_tag_name}")
    address_space_tag_category = $evm.vmdb(:classification).find_by_name(ADDRESS_SPACE_TAG_CATEGORY)
    
    selectable_networks[nil] = "ERROR: No Networks with " +
      "Tag <#{destination_tag ? destination_tag.parent.description : NETWORK_PURPOSE_TAG_CATEGORY}: #{destination_tag ? destination_tag.description : network_purpose_tag_name}> " +
      "and Tag Category <#{address_space_tag_category ? address_space_tag_category.description : ADDRESS_SPACE_TAG_CATEGORY}>" +
      " on Provider <#{destination_provider_name}>"
  elsif visible_and_required && selectable_networks.length > 1
    selectable_networks[nil] = "--- Select <#{destination_provider_name}> Destination Network"
  end
  
  # create dialog element
  dialog_field = $evm.object
  dialog_field['data_type'] = "string"
  dialog_field['visible']   = visible_and_required
  dialog_field['required']  = visible_and_required
  dialog_field['values']    = selectable_networks
  $evm.log(:info, "dialog_field['values'] => #{dialog_field['values']}") if @DEBUG
end
