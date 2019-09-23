# Adds the given VM to service specified on the provision request.
#
# EXPECTED
#   EVM ROOT
#     miq_provision - VM Provisioning request containing the VM to add to a service
#
module RedHatConsulting_Utilities
  module Automate
    module Infrastructure
      module VM
        module Provisioning
          class AddVMToService
            include RedHatConsulting_Utilities::StdLib::Core

            def initialize(handle = $evm)
              @handle = handle
              @DEBUG = false
            end

            def main
              # Get provisioning object
              prov = @handle.root['miq_provision']
              error('Provisioning request not found') if prov.nil?
              @handle.log(:info, "Provision:<#{prov.id}> Request:<#{prov.miq_provision_request.id}> Type:<#{prov.type}>")
              @handle.log(:info, "@handle.root['miq_provision'].attributes => {") if @DEBUG
              prov.attributes.sort.each { |k, v| @handle.log(:info, "\t#{k} => #{v}") } if @DEBUG
              @handle.log(:info, '}') if @DEBUG

              # get the VM
              vm = prov.vm
              error('VM on provisining request not found') if vm.nil?
              @handle.log(:info, "vm = #{vm}") if @DEBUG

              # get the service
              ws_values = prov.options[:ws_values]
              service_id = ws_values[:service_id] if ws_values
              if service_id
                service = @handle.vmdb('service').find_by_id(service_id)

                # add the VM to the service
                vm.add_to_service(service)
                @handle.log(:info, "Added VM to service: { :vm => '#{vm.name}', :service => '#{service.name}', :service_id => '#{service.id}' }")
              elsif vm.service
                @handle.log(:info, "ID of Service to add VM to not found, but VM is already a member of a service: '#{vm.service.name}'")
              else
                @handle.log(:warn, "ID of Service to add VM to not found.")
              end
            rescue => err
              @handle.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
              @handle.root['ae_result'] = 'error'
            end
          end
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  RedHatConsulting_Utilities::Automate::Infrastructure::VM::Provisioning::AddVMToService.new.main()
end
