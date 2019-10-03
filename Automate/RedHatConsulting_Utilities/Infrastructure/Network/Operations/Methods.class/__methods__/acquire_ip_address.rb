# Attempts to aquire an IP address using the DDI provider for the given network.
#
# @param network_name_parameter_name String Name of the parameter that contains the network name to get an IP address for.
#
# @set aquired_ip_address String IP address aquired fomr the DDI provider for the given network.

#/ Infrastructure / Network / Operations / Methods / acquire_ip_address
module RedHatConsulting_Utilities
  module Infrastructure
    module Network
      module Operations
        module Methods
          class AcquireIpAddress

            include RedHatConsulting_Utilities::StdLib::Core
            DDI_PROVIDERS_URI = 'Infrastructure/Network/DDIProviders'.freeze

            def initialize(handle = $evm)
              @handle = handle
              @network_configurations         = {}
              @missing_network_configurations = {}
              @DEBUG = true
            end

            def main
              begin
                vm,options = get_vm_and_options()

                network_name_parameter_name = get_param(:network_name_parameter_name)
                log(:info, "network_name_parameter_name => #{network_name_parameter_name}")
                network_name                = get_param(network_name_parameter_name) || get_param("dialog_#{network_name_parameter_name}") || options[network_name_parameter_name.to_sym] || options["dialog_#{network_name_parameter_name}".to_sym]

                if !network_name.blank?
                  network_configuration       = get_network_configuration(network_name)
                  log(:info, "network_name_parameter_name => #{network_name_parameter_name}") if @DEBUG
                  log(:info, "network_name                => #{network_name}")                if @DEBUG
                  log(:info, "network_configuration       => #{network_configuration}")       if @DEBUG

                  # determine the DDI provider
                  ddi_provider = network_configuration['network_ddi_provider']
                  log(:info, "ddi_provider => #{ddi_provider}") if @DEBUG

                  # instantiate instance to acquire IP
                  begin
                    log(:info, "Acquire IP address using DDI Provider <#{ddi_provider}>") if @DEBUG

                    @handle.root['network_name'] = network_name
                    @handle.instantiate("#{DDI_PROVIDERS_URI}/#{ddi_provider}#acquire_ip_address")
                    acquired_ip_address = get_param(:acquired_ip_address)
                    log(:info, "Acquired IP address <#{acquired_ip_address}> using DDI Provider <#{ddi_provider}>")
                    
                    ensure
                    
                    success = @handle.root['ae_result'] == nil || @handle.root['ae_result'] == 'ok'
                    reason  = @handle.root['ae_reason'] if !success

                    # clean up root
                    @handle.root['ae_result'] = 'ok'
                    @handle.root['ae_reason'] = "Acquired IP address <#{acquired_ip_address}> for VM <#{vm.name}>"

                    # clean up after call
                    @handle.root['network_name']       = nil
                    @handle.root['acquired_ip_address'] = nil
                  end
                  error("Error acquiring IP address using DDI Provider <#{ddi_provider}>: #{reason}") if !success
                else
                  log(:warn, "No value for the expected network name parameter <#{network_name_parameter_name}> was given. Skipping aquiring IP address.")
                end

                # set the acquired IP
                @handle.object['acquired_ip_address'] = acquired_ip_address
                @handle.set_state_var(:acquired_ip_address, acquired_ip_address)

                # set destination IP address to acquired IP address
                @handle.object['destination_ip_address'] = acquired_ip_address
                @handle.set_state_var(:destination_ip_address, acquired_ip_address)

                @handle.log(:info, "$evm.object['acquired_ip_address'] => #{@handle.object['acquired_ip_address']}") if @DEBUG
              end
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
            NETWORK_CONFIGURATION_URI       = 'Infrastructure/Network/Configuration'.freeze
            def get_network_configuration(network_name)
              if @network_configurations[network_name].blank? && @missing_network_configurations[network_name].blank?
                begin
                  escaped_network_name                  = network_name.gsub(/[^a-zA-Z0-9_\.\-]/, '_')
                  @network_configurations[network_name] = @handle.instantiate("#{NETWORK_CONFIGURATION_URI}/#{escaped_network_name}")

                  if escaped_network_name =~ /^dvs_/ && @network_configurations[network_name]['network_address_space'].blank?
                    escaped_network_name                  = escaped_network_name[/^dvs_(.*)/, 1]
                    @network_configurations[network_name] = @handle.instantiate("#{NETWORK_CONFIGURATION_URI}/#{escaped_network_name}")
                  end
                rescue
                  @missing_network_configurations[network_name] = "WARN: No network configuration exists"
                  log(:warn, "No network configuration for Network <#{network_name}> (escaped <#{escaped_network_name}>) exists")
                end
              end
              return @network_configurations[network_name]
            end

          end
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  RedHatConsulting_Utilities::Infrastructure::Network::Operations::Methods::AcquireIpAddress.new.main
end
