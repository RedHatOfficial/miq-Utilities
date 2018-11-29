# Performs a VM refresh until VM IP hostnames are available.

module RedHatConsulting_Utilities
  module Automate
    module Infrastructure
      module VM
        module Provisioning
          class WaitForVmHostnames
          include RedHatConsulting_Utilities::StdLib::Core

            def initialize(handle = $evm)
              @handle = handle
              @DEBUG = true
            end

            def main
              # get VM and options
              vm, options = get_vm_and_options()
              error("vm parameter not found") if vm.blank?

              # ensure VM IP addresses are set
              if vm.hostnames.first.nil?
                log(:info, "VM <#{vm.name}> hostname addresses not detected yet, perform VM refresh and retry.") if @DEBUG
                vm.refresh
                automate_retry(30, 'Wait for VM <#{vm.name}> refresh to detect VM hostname')
              else
                log(:info, "vm.hostnames => #{vm.hostnames.join(',')}") if @DEBUG
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
  RedHatConsulting_Utilities::Automate::Infrastructure::VM::Provisioning::WaitForVmHostnames.new.main()
end

