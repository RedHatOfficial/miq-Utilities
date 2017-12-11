#
# Description: 	This method updates the service provision status and
#				sends an email with that update if the update is an error or if email_only_on_error is false.
#
# Required inputs:
#   * status
#
# Optional inputs:
#   * email_only_on_error - Defaults to true.
#
module ManageIQ
  module Automate
    module Service
      module Provisioning
        module StateMachines
          module ServiceProvision_Template
            class UpdateServiceProvisionStatus
              DEBUG = false
              SERVICE_PROVISION_UPDATE_EMAIL_URI = 'Service/Provisioning/Email/ServiceProvision_Update'
              
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
                
                # send email on error or if not send only on error
                if @handle.root['ae_result'] == "error" || !@handle.inputs['email_only_on_error']
                  send_service_provision_update_email(prov, updated_message)
                end

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
                updated_message += "Current Retry Number [#{@handle.root['ae_state_retries']}]" if @handle.root['ae_result'] == 'retry'
                prov.miq_request.user_message = updated_message
                prov.message = status

                updated_message
              end
                
              # Send an email about the status of the VM provisioning.
              #
              # @param prov           Provisioning task to send the update email about
              # @param update_message Updatd provisioning message
              #
              # @return true if success sending email, false otherwise.
              def send_service_provision_update_email(prov, update_message)
                @handle.log(:info, "send_service_provision_update_email: START: { prov => #{prov}, updated_message => #{updated_message} }") if DEBUG

                # save current state of root
                current_root_prov      = @handle.root['prov']
                current_miq_request    = @handle.root['miq_request']
                current_root_ae_result = @handle.root['ae_result']
                current_root_ae_reason = @handle.root['ae_reason']
                

                begin
                  # instantiate the state machine to send a provision update email
                  @handle.root['ae_result']                        = nil
                  @handle.root['ae_reason']                        = nil
                  @handle.root['prov']                             = prov
                  @handle.root['miq_request']                      = prov.miq_request
                  @handle.root['service_provision_update_message'] = update_message
                  @handle.instantiate(SERVICE_PROVISION_UPDATE_EMAIL_URI)
                  success = true
                ensure
                  success = @handle.root['ae_result'] == nil || @handle.root['ae_result'] == 'ok'
                  success = @handle.root['ae_reason'] if !success

                  # clean up root
                  @handle.root['service_provision_update_message'] = nil

                  # reset root to previous state
                  @handle.root['prov']        = current_root_prov
                  @handle.root['ae_result']   = current_root_ae_result
                  @handle.root['ae_reason']   = current_root_ae_reason
                  @handle.root['miq_request'] = current_miq_request
                end

                @handle.log(:info, "send_service_provision_update_email: END: { prov => #{prov}, updated_message => #{updated_message} }") if DEBUG
                return success
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
