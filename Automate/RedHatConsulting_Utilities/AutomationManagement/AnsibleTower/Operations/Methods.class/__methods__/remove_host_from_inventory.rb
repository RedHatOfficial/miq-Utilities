# Author: Brant Evans    (bevans@redhat.com)
# Author: Jeffrey Cutter (jcutter@redhat.com
# Author: Andrew Becker  (anbecker@redhat.com)
# License: GPL v3
#
# Description: Remove a host from an Ansible Inventory via API

require 'rest_client'
require 'json'

module AutomationManagement
  module AnsibleTower
    module Operations
      module Methods
        class RemoveHostFromInventory
          include RedHatConsulting_Utilities::StdLib::Core
          
          TOWER_CONFIGURATION_URI = 'Integration/AnsibleTower/Configuration/default'.freeze

          def initialize(handle = $evm)
            @handle = handle
            @DEBUG = false
            @tower_config = @handle.instantiate(TOWER_CONFIGURATION_URI)
            @handle.log(:info, "Resolved Ansible Tower Configuration URI: #{@tower_config.name}") if @DEBUG
          end

          def check_configuration
            error("Ansible Tower Config not found at #{TOWER_CONFIGURATION_URI}") if @tower_config.blank?
            error("Ansible Tower URL not set") if @tower_config['tower_url'].blank?
            error("Ansible Tower Username not set") if @tower_config['tower_username'].blank?
            error("Ansible Tower Password not set") if @tower_config['tower_password'].blank?
          end

          def tower_request_url(api_path)
            api_version = @tower_config['tower_api_version']
            tower_url = @tower_config['tower_url']
            # build the URL for the REST request
            url = "#{tower_url}/api/#{api_version}/#{api_path}"
            # Tower expects the api path to end with a "/" so guarantee that it is there
            # Searches and filters don't like trailing / so exclude if includes =
            url << '/' unless url.end_with?('/') || url.include?('=')
            @handle.log(:info, "Call Tower API URL: <#{url}>") if @DEBUG
            return url
          end

          def tower_request(action, api_path, payload=nil)
            # build the REST request
            params = {
              :method     => action,
              :url        => tower_request_url(api_path),
              :user       => @tower_config['tower_username'],
              :password   => @tower_config['tower_password'],
              :verify_ssl => @tower_config['tower_verify_ssl'],
              :timeout    => @tower_config['tower_api_timeout']
              }
            params[:payload] = payload unless payload.nil?
            params[:headers] = {:content_type => 'application/json' } unless payload.nil?
            @handle.log(:info, "Tower request payload: #{payload.inspect}") if (@DEBUG and !payload.nil?)

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
              response_json = JSON.parse(response) unless response.body.blank?
            else
              error("Error calling Ansible Tower REST API. Response Code: <#{response.code}>  Response: <#{response.inspect}>")
            end
            return response_json
          end

          def main 
          
            @handle.log(:info, "Starting Ansible Tower Routine to remove host from inventory")
            
            dump_root()    if @DEBUG
            
            check_configuration
            
            # Get Ansible Tower Inventory ID from Inventory Name
            inventory_name = @tower_config['tower_inventory_name']
            error('Ansible Tower Inventory not defined. Update configuration at #{@tower_config.name}') if inventory_name.blank?
            @handle.log(:info, "inventory_name: #{inventory_name}") if @DEBUG
            api_path = "inventories?name=#{CGI.escape(inventory_name)}"
            inventory_result = tower_request(:get, api_path)
            inventory_id = inventory_result['results'].first['id'] rescue nil
            error("Unable to determine Tower inventory_id from inventory name: #{inventory_name}") if inventory_id.blank?
            @handle.log(:info, "inventory_id: #{inventory_id}") if @DEBUG
              
            # Get VM hostname
            vm,options = get_vm_and_options()
            error('Unable to find VM') if vm.blank?
            # determine vm hostname, first try to get hostname entry, else use vm name
            vm_hostname   = vm.hostnames.first unless vm.hostnames.blank?
            vm_hostname ||= vm.name
            @handle.log(:info, "VM Hostname determined for Ansible Tower Inventory: #{vm_hostname}") if @DEBUG
            error('Unable to determine VM Hostname') if vm_hostname.blank?

            # Check That VM already exists in inventory
            api_path = "inventories/#{inventory_id}/hosts/?name=#{vm_hostname}"
            host_result = tower_request(:get, api_path)
            host_present_in_inventory = host_result['count'] > 0
            if !host_present_in_inventory
              @handle.log(:info, "VM #{vm_hostname} does not exist in Ansible Tower Inventory [ #{inventory_name} ], done.")
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
            @handle.log(:info, "VM #{vm_hostname} successfully removed from Ansible Tower inventory [ #{inventory_name} ]")
            exit MIQ_OK
          end
 
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  AutomationManagement::AnsibleTower::Operations::Methods::RemoveHostFromInventory.new.main
end
