# Performs a VM refresh until VM IP addresses are available.
# If a destination_ip option is set then will wait for that IP to be available
#
# @param destination_ip Optional.
module RedHatConsulting_Utilities
  module Automate
    module Infrastructure
      module VM
        module Provisioning
          class WaitForVmIPAddresses

            include RedHatConsulting_Utilities::StdLib::Core
            def initialize(handle = $evm)
              @handle = handle
              @DEBUG = true
            end

            def main
              # get VM and options
              vm, options = get_vm_and_options()
              error("vm parameter not found") if vm.blank?

              # check to see if there is an expected destination ip
              expected_ip = options[:destination_ip_address] || get_param(:destination_ip_address)

              # ensure VM IP addresses are set
              if vm.ipaddresses.nil? || vm.ipaddresses.empty?
                log(:info, "VM <#{vm.name}> IP addresses not detected yet, perform VM refresh and retry.") if @DEBUG
                vm.refresh
                automate_retry(30, 'Wait for VM <#{vm.name}> refresh to detect VM IP addresses')
              elsif !expected_ip.blank? && !vm.ipaddresses.include?(expected_ip)
                log(:info, "VM <#{vm.name}> IP addresses detected but does not contain expected IP <#{expected_ip}>") if @DEBUG
                vm.refresh
                automate_retry(30, "Wait for VM <#{vm.name}> refresh to detect expected VM IP <#{expected_ip}>")
              else
                log(:info, "vm.ipaddresses => #{vm.ipaddresses}, expected_ip => #{expected_ip}") if @DEBUG
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
  RedHatConsulting_Utilities::Automate::Infrastructure::VM::Provisioning::WaitForVmIPAddresses.new.main()
end
