#
# Description: This method updates the service provision status.
# Required inputs: status
#
module ManageIQ
  module Automate
    module Service
      module Provisioning
        module StateMachines
          module ServiceProvision_Template
            class UpdateServiceProvisionStatus
              def initialize(handle = $evm)
                @handle = handle
              end

              def main
                prov = @handle.root['service_template_provision_task']

                if prov.nil?
                  @handle.log(:error, "service_template_provision_task object not provided")
                  raise "service_template_provision_task object not provided"
                end

                updated_message = update_status_message(prov, @handle.inputs['status'])

                if @handle.root['ae_result'] == "error"
                  @handle.create_notification(:level   => "error",
                                              :subject => prov.miq_request,
                                              :message => "Service Provision Error: #{updated_message}")
                  @handle.log(:error, "Service Provision Error: #{updated_message}")
                end
              end

              private

              def update_status_message(prov, status)
                updated_message  = "Server [#{@handle.root['miq_server'].name}] "
                updated_message += "Service [#{prov.destination.name}] "
                updated_message += "Step [#{@handle.root['ae_state']}] "
                updated_message += "Status [#{status}] "
                updated_message += "Message [#{prov.message}] "
                updated_message += "Current Retry Number [#{@handle.root['ae_state_retries']}]"\
                                    if @handle.root['ae_result'] == 'retry'
                prov.miq_request.user_message = updated_message
                prov.message = status

                updated_message
              end
            end
          end
        end
      end
    end
  end
end
if __FILE__ == $PROGRAM_NAME
  ManageIQ::Automate::Service::Provisioning::StateMachines::
    ServiceProvision_Template::UpdateServiceProvisionStatus.new.main
end
