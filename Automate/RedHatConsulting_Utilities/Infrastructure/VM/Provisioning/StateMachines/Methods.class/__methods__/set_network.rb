module Automate
  module Infrastructure
    module VM
      module Provisioning
        module StateMachines
          module Methods
            class SetNetwork
              include RedHatConsulting_Utilities::StdLib::Core
                
              DEBUG = false
                
              def intialize(handle = $evm)
                @handle = handle
              end
                
              def main
                # Get variables
                prov = @handle.root["miq_provision"]
                template = prov.vm_template
                error("Template not specified") if template.nil?
                
                # if a network name is provided attempt to set that network
                #  NOTE: that the given netowrk_name may not be the exact name for the network, it maybe a pattern to match a network name
                #        useful when the same subnet/vlan has different network names on different clusters
                # else ignore
                provisioning_network_name_pattern = prov.get_option(:provisioning_network_name_pattern) || prov.get_option(:ws_values)[:provisioning_network_name_pattern]
                if !provisioning_network_name_pattern.blank?
                  # determine hosts to search for the destaination network based on the given name
                  destination_hosts = []
                  host_id    = prov.get_option(:placement_host_name)
                  cluster_id = prov.get_option(:placement_cluster_name)
                  if !host_id.blank?
                    host = @handle.vmdb(:host).find_by_id(host_id)
                    destination_hosts += [host] if !host.nil?
                  elsif !cluster_id.blank?
                    cluster = @handle.vmdb(:ems_cluster).find_by_id(cluster_id)
                    destination_hosts += cluster.hosts if !cluster.nil?
                  end
                  @handle.log(:info, "destination_hosts => #{destination_hosts}") if DEBUG
                  # this really shouldn't ever happen, but check for it anyway
                  error("Could not set network for miq_provision <#{prov}> because could not determine destination host or cluster for said provision to find target network on.") if destination_hosts.empty?
                  
                  # find network that matches the given network on the host
                  possible_networks = []
                  destination_hosts.each do |host|
                    possible_networks += host.lans.select { |lan| lan.name =~ /#{provisioning_network_name_pattern}/ }
                  end
                  possible_networks = possible_networks.uniq
                  @handle.log(:info, "possible_networks => #{possible_networks}") if DEBUG
                  provisioning_network      = possible_networks.first
                  provisioning_network_name = provisioning_network.name
                  @handle.log(:info, "provisioning_network      => #{provisioning_network}")      if DEBUG
                  @handle.log(:info, "provisioning_network_name => #{provisioning_network_name}") if DEBUG
                  @handle.log(:warn, "Found more then one possible network matching <#{provisioning_network_name_pattern}> on possible destination hosts <#{destination_hosts}> for miq_provision <#{prov}>. Using first found matching network <#{provisioning_network}>.") if possible_networks.length > 1
                  
                  # determine if the provisioning network is a distributed vswitch or not
                  if !(provisioning_network_name =~ /^dvs_/) && provisioning_network && (provisioning_network.respond_to?(:switch) && provisioning_network.switch.shared)
                    provisioning_network_name = "dvs_#{provisioning_network_name}"
                  end
                  @handle.log(:info, "updated provisioning_network_name => #{provisioning_network_name}") if DEBUG
  
                  # if a cloud network
                  # else infrastructure network
                  vm_fields = []
                  if provisioning_network.respond_to?(:cloud_network)
                    prov.set_option(:cloud_subnet,                provisioning_network.id)
                    prov.set_option(:cloud_network,               provisioning_network.cloud_network_id)

                    @handle.log(:info, "Provisioning object <:cloud_subnet> updated with <#{prov.get_option(:cloud_subnet)}>")
                    @handle.log(:info, "Provisioning object <:cloud_network> updated with <#{prov.get_option(:cloud_network)}>")

                    # TODO: this really needs to be set before ever getting to networking, but this is how the old code used to work when
                    #       networking was set in the `create_provision_requests` step. DOn't have a test infra set up right now to figure out new plan for cloud.
                    #       This very likely almost certainly does not work, but is left here as a reminder for "someday"
                    prov.set_option(:placement_availability_zone, provisioning_network.availability_zone_id)
                  else
                    # if provider is RHV and CFME version 5.9 or above use VLAN profile ID
                    # else use vlan name
                    if (template.ext_management_system.type =~ /Redhat/) && (Gem::Version.new(@handle.root['miq_server'].version) >= Gem::Version.new('5.9'))
                      vnic_profile_id = Automation::Infrastructure::VM::RedHat::Utils.new(template.ext_management_system).vnic_profile_id(provisioning_network_name)
                      @handle.log(:info, "prov.set_vlan: vnic_profile_id => #{vnic_profile_id}") if DEBUG
                      prov.set_vlan(vnic_profile_id)
                    else
                      @handle.log(:info, "prov.set_vlan: provisioning_network_name => #{provisioning_network_name}") if DEBUG
                      prov.set_vlan(provisioning_network_name)
                    end
                    @handle.log(:info, "Provisioning object <:vlan> updated with <#{prov.get_option(:vlan)}>")
                  end
                  prov.set_option(:network_adapters, 1)
                else
                  @handle.log(:warn, "No provisioning network name provided for miq_provision <#{prov}>.")
                end
              end # end main
              
            end
          end
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  Automate::Infrastructure::VM::Provisioning::StateMachines::Methods::SetNetwork.new.main
end
