module Automate
  module Infrastructure
    module Network
      module Operations
        module Methods
          class NotifyAquiredIP
            include RedHatConsulting_Utilities::StdLib::Core
            
            def intialize(handle = $evm)
              @handle = handle
            end
                
            def main
              vm,options          = get_vm_and_options()
              acquired_ip_address = get_param(:acquired_ip_address)
              $evm.create_notification(:level => 'info', :message => "Aquired IP <#{acquired_ip_address}> for VM <#{vm.name}>.")
            end
            
          end
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  Automate::Infrastructure::Network::Operations::Methods::NotifyAquiredIP.new.main
end
