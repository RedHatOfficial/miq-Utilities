module RedHatConsulting_Utilities
  module Automate
    module Infrastructure
      module VM
        module Provisioning
          module Placement
            class VMWare_Customize
              include RedHatConsulting_Utilities::StdLib::Core

              # Get the vm provsining customization configuration.
              #
              # @return VM provisining configuration
              VM_PROVISIONING_CONFIG_URI = 'Infrastructure/VM/Provisioning/Configuration/default'

              def initialize(handle = $evm)
                @handle   = handle
                @settings = RedHatConsulting_Utilities::StdLib::Core::Settings.new()
                @DEBUG    = false
              end

              def main
                # Get provisioning object
                prov = @handle.root['miq_provision']
                error('Provisioning request not found') if prov.nil?
                log(:info, "Provision:<#{prov.id}> Request:<#{prov.miq_provision_request.id}> Type:<#{prov.type}>")

                dump_root_attribute('miq_provision') if @DEBUG

                # log(:info, "prov.attributes => {") if @DEBUG
                # prov.attributes.sort.each {|k, v| log(:info, "\t#{k} => #{v}")} if @DEBUG
                # log(:info, "}") if @DEBUG

                # get the datacenter
                template = prov.vm_template
                datacenter = template.v_owning_datacenter

                # determine cutsomized placement folder
                vm_provisioning_config = get_vm_provisioning_config()
                vmware_folder = vm_provisioning_config['vmware_folder']

                vsphere_fully_qualified_folder = "#{datacenter}/#{vmware_folder}"

                log(:info, "vmware_folder is: [#{vmware_folder}]")
                log(:info, "vsphere_fully_qualified_folder is: [#{vsphere_fully_qualified_folder}]")
                # update placement folder
                log(:info, "Provisioning object <:placement_folder_name> curent value <#{prov.options[:placement_folder_name].inspect}>") if @DEBUG
                prov.set_folder(vsphere_fully_qualified_folder)
                log(:info, "Provisioning object <:placement_folder_name> updated with <#{prov.options[:placement_folder_name].inspect}>")

                # We keep the VM powered off so we can get the MAC address and update IPAM
                # before first boot.
                if @settings.get_setting(:global, :vm_auto_start_suppress)
                  prov.set_option(:vm_auto_start, [false, 0])
                  log(:info, "Provisioning object <:vm_auto_start> updated with <#{prov.options[:vm_auto_start].inspect}>")
                end
              end

              private

              def get_vm_provisioning_config()

                provisioning_config = @handle.instantiate(VM_PROVISIONING_CONFIG_URI)
                error("VM Provisioning Configuration not found") if provisioning_config.nil?

                return provisioning_config
              end
            end
          end
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  RedHatConsulting_Utilities::Automate::Infrastructure::VM::Provisioning::Placement::VMWare_Customize.new.main
end


