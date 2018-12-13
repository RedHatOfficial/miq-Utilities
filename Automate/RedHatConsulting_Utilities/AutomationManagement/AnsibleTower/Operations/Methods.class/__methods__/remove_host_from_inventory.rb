# Author: Brant Evans    (bevans@redhat.com)
# Author: Jeffrey Cutter (jcutter@redhat.com
# Author: Andrew Becker  (anbecker@redhat.com)
# License: GPL v3
#
# Description: Remove a host from an Ansible Inventory via API

module AutomationManagement
  module AnsibleTower
    module Operations
      module Methods
        class RemoveHostFromInventory < Integration::AnsibleTower::AnsibleTowerBase

          def initialize(handle = $evm)
            super(handle)
            @DEBUG = false
          end
          
          def main 
            @handle.log(:info, "Starting Ansible Tower Routine to remove host from Ansible Tower inventory [ #{@tower_inventory_name} ]")
            dump_root()    if @DEBUG
            vm,options = get_vm_and_options()
            vm_inventory_hostname = inventory_hostname(vm)
            
            # Check if VM already exists in inventory
            begin
              host_id = tower_host_id(vm)
            rescue
              log(:error, "Unable to determine if host [ #{vm_inventory_hostname} ] is in Ansible Tower Inventory [ #{@tower_inventory_name} ]")
              error("Error making Ansible Tower API Call. #{e.to_s}")
            end
            
            if host_id.nil?
              @handle.log(:info, "VM [ #{vm_inventory_hostname} ] does not exist in Ansible Tower Inventory [ #{@tower_inventory_name} ], done.")
              exit MIQ_OK
            end
            
            # Remove the host from the Ansible Tower Inventory
            api_path = "inventories/#{@tower_inventory_id}/hosts/"
            payload = {
              :id => host_id,
              :disassociate => true
            }.to_json
            
            begin
              tower_request(:post, api_path, payload)
            rescue
              log(:error, "Unable to remove host [ #{vm_inventory_hostname} ] from Ansible Tower Inventory  [ #{@tower_inventory_name} ]")
              error("Error making Ansible Tower API Call. #{e.to_s}")
            end

            # Verify that the host has been remove from the inventory
            begin
              host_present_in_inventory = vm_in_inventory?(vm)
            rescue => e
              log(:error, "Unable to determine if host [ #{vm_inventory_hostname} ] is in Ansible Tower Inventory [ #{@tower_inventory_name} ]")
              error("Error making Ansible Tower API Call. #{e.to_s}")
            end
            
            if host_present_in_inventory
              error("Failed to remove #{vm_inventory_hostname} to Ansible Inventory [ #{@tower_inventory_name} ].")
            end
            
            @handle.log(:info, "VM #{vm_inventory_hostname} successfully removed from Ansible Tower inventory [ #{@tower_inventory_name} ]")
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
