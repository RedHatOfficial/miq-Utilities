# Author: Brant Evans    (bevans@redhat.com)
# Author: Jeffrey Cutter (jcutter@redhat.com
# Author: Andrew Becker  (anbecker@redhat.com)
# License: GPL v3
#
# Description: Add a host from an Ansible Inventory via API

module AutomationManagement
  module AnsibleTower
    module Operations
      module Methods
        class AddHostToInventory < Integration::AnsibleTower::AnsibleTowerBase
          
          include RedHatConsulting_Utilities::StdLib::Core
          
          def initialize(handle = $evm)
            super(handle)
            @DEBUG = false
          end
          
          # Get the ip address to set as the 'ansible_host' host variable
          # if an IP address cannot be found, return nil.
          # More info about the 'ansible_host' var:
          # - https://docs.ansible.com/ansible/latest/user_guide/intro_inventory.html#list-of-behavioral-inventory-parameters
          #
          # @param vm object
          def determine_host_ip_address(vm)
            if vm.ipaddresses.blank?
              log(:info, "Unable to determine VM IP address for Ansible Tower Inventory - no IP Addresses associated with VM.")
              return nil
            end
            destination_ip = get_param(:destination_ip_address)
            log(:info, "Host Destination IP Address => #{destination_ip}" )
            ip_address = vm.ipaddresses.include?(destination_ip) ? destination_ip : vm.ipaddresses.first
            log(:info, "Discovered IP Address for Ansible Tower Inventory => #{ip_address}" )
            return ip_address
          end

          def main 
            @handle.log(:info, "Starting Routine to add a host to an Ansible Tower Inventory [ #{@tower_inventory_name} ]") if @DEBUG
            dump_root()    if @DEBUG
            vm,options = get_vm_and_options()
            vm_inventory_hostname = inventory_hostname(vm)
            
            # Check if VM already exists in inventory
            begin
              host_id = tower_host_id(vm)
            rescue
              log(:error, "Unable to determine if host is in Ansible Tower Inventory [ #{@tower_inventory_name} ]")
              error("Error making Ansible Tower API Call. #{e.to_s}")
            end
            
            # Add the host to Ansible Tower Inventory
            api_path = host_id.nil? ? "hosts" : "hosts/#{host_id}"
            host_management_action = host_id.nil? ? :post : :patch
            
            # If the ipaddress cannot be determined, set ansible_host to 
            # the inventory_hostname
            # This is default connection behavior if ansible_host is not set
            vm_ip_address = determine_host_ip_address(vm)
            host_variables = {
              :ansible_host => vm_ip_address || vm_inventory_hostname,
            }.to_json

            payload = {
              :name      => vm_inventory_hostname,
              :inventory => @tower_inventory_id,
              :enabled   => true,
              :variables => host_variables
            }.to_json
 
            begin
              tower_request(host_management_action, api_path, payload)
            rescue
              log(:error, "Unable to add host [ #{vm_inventory_hostname} ] to Ansible Tower inventory [ @tower_inventory_name ]")
              error("Error making Ansible Tower API Call. #{e.to_s}")
            end

            # Verify if the name is in the inventory
            begin
            host_present_in_inventory = vm_in_inventory?(vm)
            rescue => e
              log(:error, "Unable to determine if host [ #{vm_inventory_hostname} ] is in Ansible Tower Inventory [ #{@tower_inventory_name} ]")
              error("Error making Ansible Tower API Call. #{e.to_s}")
            end
              
            if !host_present_in_inventory
              error("Failed to add #{vm_inventory_hostname} to Ansible Inventory [ #{@tower_inventory_name} ].")
            end
            @handle.log(:info, "VM #{vm_inventory_hostname} with IP address #{vm_ip_address} successfully added to Ansible Tower inventory [ #{@tower_inventory_name} ]")
            exit MIQ_OK
          end
          
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  AutomationManagement::AnsibleTower::Operations::Methods::AddHostToInventory.new.main
end
