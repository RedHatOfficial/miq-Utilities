# Attempts to retire an IP address by using the DDI provider for the network of the provided VM.
#
# @set retired_ip_address String IP address retired from the DDI provider for the network of the provided VM.
#

module RedHatConsulting_Utilities
  module Infrastructure
    module Network
      module Operations
        module Methods
          class ReleaseIPAddress

            include RedHatConsulting_Utilities::StdLib::Core
            DDI_PROVIDERS_URI = 'Infrastructure/Network/DDIProviders'.freeze

            def initialize(handle = $evm)
              @handle = handle
              @DEBUG = false
            end

            def main
              begin
                dump_root if @DEBUG

                vm,options = get_vm_and_options()

                # NOTE: this is hard coded to the first network interface because can't
                #       decide how to determine which network interfaces to release the IPs for...
                #
                # TODO: don't hard code this to first interface
                network = vm.hardware.nics[0].lan
                log(:info, "Releaseing IP Address on network <#{network}> for VM <#{vm.name}>") if @DEBUG

                # TODO: figure out some workaround to this issue or do something else here.
                # deal with https://bugzilla.redhat.com/show_bug.cgi?id=1572917
                if network.nil?
                  log(
                    :warn,
                    "Could not determine Network for VM <#{vm.name} to release IP address due to " +
                      "https://bugzilla.redhat.com/show_bug.cgi?id=1572917. IP address will need to be manually released. " +
                      "Ignoring & Skipping."
                    )
                  exit MIQ_OK
                end

                # find matching network configuration
                vm_network_name            = network.name
                network_configurations     = get_network_configurations()
                network_configuration      = nil
                network_configuration_name = nil
                log(:info, "network_configurations => #{network_configurations}") if @DEBUG
                network_configurations.each do |configuration_name, configuraiton|
                  if vm_network_name =~ /#{configuration_name}/
                    network_configuration_name = configuration_name
                    network_configuration      = configuraiton
                    break
                  end
                end
                log(:info, "vm_network_name            => #{vm_network_name}")            if @DEBUG
                log(:info, "network_configuration_name => #{network_configuration_name}") if @DEBUG
                log(:info, "network_configuration      => #{network_configuration}")      if @DEBUG

                log(:warn, "Could not find network configuration for VM network <#{vm_network_name}>. Skipping release IP.") if network_configuration.nil?

                # determine the DDI provider
                ddi_provider = network_configuration['network_ddi_provider'] if network_configuration
                log(:info, "ddi_provider => #{ddi_provider}") if @DEBUG

                if !ddi_provider.blank?
                  # instantiate instance to aquire IP
                  begin
                    log(:info, "Release IP address using DDI Provider <#{ddi_provider}>") if @DEBUG

                    @handle.root['network_name']               = vm_network_name
                    @handle.root['network_configuration_name'] = network_configuration_name
                    @handle.instantiate("#{DDI_PROVIDERS_URI}/#{ddi_provider}#release_ip_address")
                    released_ip_address = get_param(:released_ip_address)

                    log(:info, "Released IP address <#{released_ip_address}> using DDI Provider <#{ddi_provider}>") if @DEBUG
                    ensure
                    success = @handle.root['ae_result'] == nil || $evm.root['ae_result'] == 'ok'
                    reason  = @handle.root['ae_reason'] if !success

                    # clean up root
                    @handle.root['ae_result'] = nil
                    @handle.root['ae_reason'] = nil

                    # clean up after call
                    @handle.root['network_name']               = nil
                    @handle.root['network_configuration_name'] = nil
                    @handle.root['released_ip_address']        = nil

                    @handle.root['ae_reason'] = "Released IP address <#{released_ip_address}>"
                  end
                else
                  @handle.root['ae_reason'] = "Can not retire IP for VM <#{vm.name}>, no DDI Provider found for Network <#{vm_network_name}>."
                  @handle.root['ae_level']  = :warning
                end

                # set the released IP
                @handle.object['released_ip_address'] = released_ip_address
                @handle.set_state_var(:released_ip_address, released_ip_address)
                @handle.root['ae_result'] = 'ok'
              end
            end

          end
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  RedHatConsulting_Utilities::Infrastructure::Network::Operations::Methods::ReleaseIPAddress.new.main()
end
