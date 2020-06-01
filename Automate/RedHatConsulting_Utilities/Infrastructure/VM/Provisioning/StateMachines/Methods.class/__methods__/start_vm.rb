
# Starts / Powers on VM and then waits for the VM to be in a powerd on state.
#
# @source https://pemcg.gitbooks.io/mastering-automation-in-cloudforms-4-2-and-manage/content/customising_vm_provisioning/chapter.html#_start_vm
#

module RedHatConsulting_Utilities
  module Automate
    module Infrastructure
      module VM
        module Provisioning
          class StartVM

            include RedHatConsulting_Utilities::StdLib::Core
            def initialize(handle = $evm)
              @handle = handle
              @DEBUG = false
            end

            def main
              begin
                # get VM and options
                vm, options = get_vm_and_options()
                error("vm parameter not found") if vm.blank?
                
                $evm.log(:info, "Current VM power state = #{vm.power_state}")
                unless vm.power_state == 'on'
                  vm.start
                  vm.refresh
                  $evm.root['ae_result'] = 'retry'
                  $evm.root['ae_retry_interval'] = '30.seconds'
                else
                  $evm.root['ae_result'] = 'ok'
                end
              rescue => err
                $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
                $evm.root['ae_result'] = 'error'
              end
            end

          end
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  RedHatConsulting_Utilities::Automate::Infrastructure::VM::Provisioning::StartVM.new.main()
end
