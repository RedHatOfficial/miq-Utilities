# Author: Brant Evans    (bevans@redhat.com)
# Author: Jeffrey Cutter (jcutter@redhat.com
# Author: Andrew Becker  (anbecker@redhat.com)
# License: GPL v3
#
# Description: Remove a host from an Ansible Inventory via API

require 'rest_client'
require 'json'

@DEBUG = false

TOWER_CONFIGURATION_URI = 'Integration/AnsibleTower/Configuration/default'.freeze
TOWER_CONFIG            = $evm.instantiate(TOWER_CONFIGURATION_URI)

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

def tower_request(action, api_path, payload=nil)

  server         = TOWER_CONFIG['tower_host']
  api_version    = TOWER_CONFIG['api_version']
  tower_provider = $evm.vmdb(:ems).where("type = 'ManageIQ::Providers::AnsibleTower::AutomationManager'").find { |tower| tower.url =~ /#{server}/ }
  username       = tower_provider.authentication_userid
  password       = tower_provider.authentication_password
  $evm.log(:info, "server: #{server}, api_version: #{api_version}, username: #{username}") if @DEBUG

  # build the URL for the REST request
  url = "https://#{server}/api/#{api_version}/#{api_path}"

  # Tower expects the api path to end with a "/" so guarantee that it is there
  # Searches and filters don't like trailing / so exclude if includes =
  url << '/' unless url.end_with?('/') || url.include?('=')
  $evm.log(:info, "Call Tower API URL: <#{url}>") if @DEBUG
  $evm.log(:info, "Tower request payload: #{payload.inspect}")

  # build the REST request
  params = {
    :method     => action,
    :url        => url,
    :user       => username,
    :password   => password,
    :verify_ssl => TOWER_CONFIG['verify_ssl'],
    :timeout    => TOWER_CONFIG['api_timeout']
  }
  params[:payload] = payload unless payload.nil?
  params[:headers] = {:content_type => 'application/json' } unless payload.nil?

  # call the Ansible Tower REST service
  begin
    response = RestClient::Request.new(params).execute
  rescue => e
    error("Error making Tower request: #{e.response}")
  end
 
  # Parse Tower Response
  response_json = {}  
  # treat all 2xx responses as acceptable
  if response.code.to_s =~ /2\d\d/
    response_json = JSON.parse(response) unless response.body.empty?
  else
    error("Error calling Ansible Tower REST API. Response Code: <#{response.code}>  Response: <#{response.inspect}>")
  end

  response_json

end

begin  

  dump_root()    if @DEBUG
  dump_current() if @DEBUG

  $evm.log(:info, "Starting Ansible Tower integration routine to add a host to the inventory")
  
  #check config information
  error("Ansible Tower Config not found at #{TOWER_CONFIGURATION_URI}") if ( TOWER_CONFIG.nil? or TOWER_CONFIG['server'] == 'tower.example.com' )
  
  # Get Ansible Tower Inventory ID from Inventory Name
  inventory_name = TOWER_CONFIG['inventory_name']
  $evm.log(:info, "inventory_name: #{inventory_name}") if @DEBUG
  api_path = "inventories?name=#{CGI.escape(inventory_name)}"
  inventory_result = tower_request(:get, api_path)
  inventory_id = inventory_result['results'].first['id'] rescue nil
  error("Unable to determine Tower inventory_id from inventory name: #{inventory_name}") if inventory_id.blank?
  $evm.log(:info, "inventory_id: #{inventory_id}") if @DEBUG
    
  # Get VM hostname
  vm,options = get_vm_and_options()
  error('Unable to find VM') if vm.nil?
  # determine vm hostname, first try to get hostname entry, else use vm name
  vm_hostname   = vm.hostnames.first if !vm.hostnames.empty?
  vm_hostname ||= vm.name
  $evm.log(:info, "VM Hostname determined for Ansible Tower Inventory: #{vm_hostname}") if @DEBUG
  error('Unable to determine VM Hostname') if vm_hostname.blank?

  # Check That VM already exists in inventory
  api_path = "inventories/#{inventory_id}/hosts/?name=#{vm_hostname}"
  host_result = tower_request(:get, api_path)
  host_present_in_inventory = host_result['count'] > 0
  if !host_present_in_inventory
    $evm.log(:info, "VM #{vm_hostname} does not exist in Ansible Tower Inventory [ #{inventory_name} ], done.")
    exit MIQ_OK
  end
  
  # Remove the host from the Ansible Tower Inventory
  host_id = host_result['results'].first['id']
  api_path = "hosts/#{host_id}"
  tower_request(:delete, api_path)

  # Verify that the host has been remove from the inventory
  api_path = "inventories/#{inventory_id}/hosts?name=#{vm_hostname}"
  host_removed_result = tower_request(:get, api_path)
  if host_removed_result['count'] > 0
    error("Failed to remove #{vm_hostname} to Ansible Inventory [ #{inventory_name} ].")
  end
  $evm.log(:info, "VM #{vm_hostname} successfully removed from Ansible Tower inventory [ #{inventory_name} ]")
  exit MIQ_OK

rescue => err
  $evm.log(:error, "[(#{err.class})#{err}]\n#{err.backtrace.join("\n")}")
  error("Error removing host from Ansible Inventory: #{err}")
end
