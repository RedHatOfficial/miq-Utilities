# / Infra / VM / Retirement / StateMachines / CheckPreRetirement

#
# Description: This method checks to see if the VM has been powered off or suspended
#

#
# Overriding ManageIQ to add vm.refresh and to keep waiting if VM power state becomes "unknown"
#

module ManageIQ
  module Automate
    module Infrastructure
      module VM
        module Retirement
          module StateMachines
            class CheckPreRetirement
              def initialize(handle = $evm)
                @handle = handle
              end

              def main
                # Get vm from root object
                vm = @handle.root['vm']

                check_power_state(vm)
              end

              def check_power_state(vm)
                ems = vm.ext_management_system if vm
                if vm.nil? || ems.nil?
                  @handle.log('info', "Skipping check pre retirement for VM:<#{vm.try(:name)}> "\
                                      "on EMS:<#{ems.try(:name)}>")
                  return
                end

                power_state = vm.power_state
                @handle.log('info', "VM:<#{vm.name}> on Provider:<#{ems.name}> has Power State:<#{power_state}>")

                # If VM is powered off or suspended exit
                if %w(off suspended).include?(power_state)
                  # Bump State
                  @handle.root['ae_result'] = 'ok'
                elsif power_state == "never"
                  # If never then this VM is a template so exit the retirement state machine
                  @handle.root['ae_result'] = 'error'
                else
                  # perform VM refresh to get latest power state, then retry check later
                  vm.refresh
                  @handle.root['ae_result'] = 'retry'
                  @handle.root['ae_retry_interval'] = '60.seconds'
                end
              end
            end
          end
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  ManageIQ::Automate::Infrastructure::VM::Retirement::StateMachines::CheckPreRetirement.new.main
end
