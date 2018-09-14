# Determine the request type to use for the current miq_provision in the VMProvision_*/* state machine
#
# The default behavior of the "out-of-the-box" state machine of using $evm.root['miq_provision'].request_type
# can be overridden if $evm.root['miq_provision'].get_option(:custom_request_type) is set.
#
# EXPECTED
#   EVM ROOT
#     miq_provision - Provisioning request to determine the provision type
#
# SETS
#   EVM OBJECT
#     request_type - Provision type to use in the VMProvision_*/* state machine
#

module RedHatConsulting_Utilities
  module Automate
    module System
      module CommonMethods
        module StateMachineMethods
          class GetRequestType
            include RedHatConsulting_Utilities::StdLib::Core

            def initialize(handle = $evm)
              @handle = handle
              @DEBUG = true
            end

            def main
              @handle.log(:info, "START - get_request_type") if @DEBUG
              dump_root() if @DEBUG
              dump_root_attribute('miq_provision') if @DEBUG

              # get the provision object
              prov = @handle.root['miq_provision']
              error("@handle.root['miq_provision'] not found") if prov.nil?

              # find custom provision type in the provision options if it is there
              custom_request_type = prov.get_option(:custom_request_type) ||
                                    (!prov.get_option(:ws_values).blank? && prov.get_option(:ws_values)[:custom_request_type])
              @handle.log(:info, "custom_request_type => '#{custom_request_type}'") if @DEBUG

              # if a custom provision type is set use that as the provision type
              # else use the "normal" miq_provision.request_type
              @handle.object['request_type'] = if !custom_request_type.nil? && custom_request_type
                                                 custom_request_type
                                               else
                                                 @handle.root['miq_provision'].request_type
                                               end

              @handle.log(:info, "@handle.object['request_type'] => '#{@handle.object['request_type']}'")
              @handle.log(:info, 'END - get_request_type') if @DEBUG
            end
          end
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  RedHatConsulting_Utilities::Automate::System::CommonMethods::StateMachineMethods::GetRequestType.new.main()
end