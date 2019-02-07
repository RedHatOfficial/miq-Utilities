# Sends an email with an update about the service provisioning request.
#
# Designed to be called from any of the `Service/Provisioning/Email`
# instances to standerdize what email updates look like.

require 'cgi'
module RedHatConsulting_Utilities
  module Automate
    module Service
      module Provisioning
        module Email
          class ServiceProvision_Update
            include RedHatConsulting_Utilities::StdLib::Core

            PROVISIONING_TELEMETRY_PREFIX = "Provisioning_Telemetry:"

            def initialize(handle = $evm)
              @DEBUG = true
              @handle = handle
            end

            def main
              dump_root() if @DEBUG
              # get the request
              request = @handle.root['miq_request']
              request ||= @handle.root['service_template_provision_task'].miq_request unless @handle.root['service_template_provision_task'].nil?
              error("Can not find miq_request") if request.nil?

              # determine to email addresses
              to_email_addresses = determine_to_email_addresses(request)
              to_email_addresses = to_email_addresses.join(';')

              # determine current appliance
              cfme_hostname = determine_cfme_hostname()

              # determine from email address
              from_email_address = determine_from_email_address(cfme_hostname)

              # get the service provision update message
              update_message = get_param(:service_provision_update_message)
              update_message ||= request.try(:user_message)
              update_message ||= 'None'

              # send the email
              unless to_email_addresses.blank?
                send_service_provision_update_email(request, to_email_addresses, from_email_address, update_message, cfme_hostname)
              else
                warn_message = "No one to send Service Provision Update email to. Request: #{request.id}"
                log(:warn, warn_message)
                @handle.create_notification(:level => 'warning',
                                            :message => warn_message)
              end
            end

            # Determine the CFME/ManageIQ hostname
            #
            # @return CFME/ManageIQ hostname
            def determine_cfme_hostname()
              cfme_hostname = get_param(:cfme_hostname)
              cfme_hostname ||= @handle.object['appliance']
              cfme_hostname ||= @handle.root['miq_server'].hostname

              log(:info, "cfme_hostname => #{cfme_hostname}") if @DEBUG
              return cfme_hostname
            end

            # Determine the email address to send the email from
            #
            # @param cfme_hostname CFME/ManageIQ hostname the email is coming from
            #
            # @return email address to send the email from
            def determine_from_email_address(cfme_hostname)
              from_email_address = get_param(:from_email_address)
              from_email_address ||= "cfme@#{cfme_hostname}"

              log(:info, "from_email_address => #{from_email_address}") if @DEBUG
              return from_email_address
            end

            # Determin the email addresses to send the email to
            #
            # @param request miq_request to determine the to email addresses for
            #
            # @return array of email addresses to send the email to
            def determine_to_email_addresses(request)
              to_email_addresses = []

              # get requester email
              requester = request.requester
              requester_email = requester.email
              to_email_addresses.push(requester_email) unless requester_email.nil?
              log(:info, "requester_email => #{requester_email}") if @DEBUG

              # get owner email
              owner_email = request.options[:owner_email]
              to_email_addresses.push(owner_email) unless owner_email.nil?
              log(:info, "owner_email => #{owner_email}") if @DEBUG

              # get additional to addresses
              additional_to_email_address = get_param(:to_email_address)
              unless additional_to_email_address.nil?
                additional_to_email_address = additional_to_email_address.split(/[;,\s]+/)
                to_email_addresses += additional_to_email_address
              end

              # clean up email address list
              to_email_addresses = to_email_addresses.compact.uniq

              log(:info, "to_email_addresses => #{to_email_addresses}") if @DEBUG
              return to_email_addresses
            end

            # Sends an email about the service that was just provisioned:
            #
            # EXAMPLE:
            # -----------
            #
            #  Service
            #  |------------------------------------|-------------------|
            #  | Service                            | Email Test 3      |
            #  | State                              | Finishd           |
            #  | Status                             | Ok                |
            #  | Step                               | checkprovisioned  | # OPTIONAL
            #  | Message                            | Bla bal bal       |
            #  | VM Reqeusts                        | 1                 |
            #  | Approval State                     | Approved          |
            #  | Approver Notes                     | Auto              |
            #  | CloudForms Provisioning Request ID	| 10000000000373    |
            #  |------------------------------------|-------------------|
            #
            #  VMs
            #  | Name                               | IP Address(es)    | State         | Status    | Power | CloudForms Provisioning Task ID   | Last Message  |
            #  |------------------------------------|-------------------|---------------|-----------|-------|-----------------------------------|---------------|
            #  | cfme-self-service0005.example.com	| 10.15.69.128      | Provisioned   | Ok        | on    | 10000000000111                    | Bla Bla       |
            #  | cfme-self-service0006.eample.com	|                   | Error         | off       |       | 10000000000112                    | Foo Bar       |
            #  |------------------------------------|-------------------|---------------|-----------|-------|-----------------------------------|---------------|
            #
            # -----------
            def send_service_provision_update_email(request, to, from, update_message, cfme_hostname)
              log(:info, "START: send_service_provision_update_email") if @DEBUG
              log(:info, "request => #{request}") if @DEBUG
              log(:info, "request.miq_request_tasks => #{request.miq_request_tasks}") if @DEBUG

              state = request.state.capitalize
              state = 'Active' if state =~ /provisioned/i # Provisioned means that one or more VMs have provisioned,

              # which really just means cloned, so make the message more clear by just changing it to Active
              status = request.status.capitalize

              #somewhere along the line status got in differently.
              if @handle.root['ae_state_step'] == 'on_error'
                status = 'Error'
              end


              service_task = request.miq_request_tasks.select {|task| task.request_type == 'clone_to_service'}.first
              log(:info, "service_task => #{service_task}") if @DEBUG
              service = service_task.destination unless service_task.nil?

              # determine service name
              service_name = service.name unless service.nil?
              service_name ||= request.options[:dialog]['dialog_service_name'] unless request.options[:dialog].nil? || request.options[:dialog]['dialog_service_name'].nil?
              service_name ||= 'Unknown'


              # Build subject
              log(:info, "{ @handle.object.name => #{@handle.object.name} } }") if @DEBUG
              subject = "Service Provision "
              if status =~ /error/i
                subject += "Error - "
              else
                case @handle.object.name
                when /ServiceProvision_Complete/i
                  subject += "Complete - "
                when /ServiceProvision_Update/i
                  subject += "Update - #{state} #{status} - "
                when /ServiceTemplateProvisionRequest_Approved/i
                  subject += "Approved - "
                when /ServiceTemplateProvisionRequest_Denied/i
                  subject += "Denied - "
                when /ServiceTemplateProvisionRequest_Pending/i
                  subject += "Pending - "
                when /ServiceTemplateProvisionRequest_Warning/i
                  subject += "Warning - #{state} #{status} - "
                else
                  subject += "Update - #{state} #{status} - "
                end
              end
              subject += " #{service_name} (#{request.id})"

              # determine status style
              if status =~ /error/i
                status_style = 'color: red'
              else
                status_style = ''
              end

              # determine number of vm requests
              vm_requests = request.options[:dialog]['dialog_number_of_vms'] unless request.options[:dialog].nil? || request.options[:dialog]['dialog_number_of_vms'].nil?
              vm_requests ||= 'Unknown'

              # build the body
              body = ""
              body += "<h1>Service</h1>"
              body += "<table border=1 cellpadding=5 style='border-collapse: collapse;'>"
              unless service.nil?
                body += "<tr><td><b>Service</b></td><td><a href='https://#{cfme_hostname}/service/explorer/s-#{service.id}'>#{service_name}</a></td></tr>"
              else
                body += "<tr><td><b>Service</b></td><td>#{service_name}</td></tr>"
              end
              body += "<tr><td><b>State</b></td><td>#{state}</td></tr>"
              body += "<tr><td><b>Status</b></td><td><span style='#{status_style}'>#{status}</span></td></tr>"
              body += "<tr><td><b>Step</b></td><td>#{@handle.root['ae_state']}</td></tr>" unless @handle.root['ae_state'].nil?
              body += "<tr><td><b>Message</b></td><td>#{CGI::escapeHTML(update_message)}</td></tr>"
              body += "<tr><td><b>VM Requests</b></td><td>#{vm_requests}</td></tr>"
              body += "<tr><td><b>Approval State</b></td><td>#{request.approval_state.capitalize}</td></tr>"
              body += "<tr><td><b>Approver Notes</b></td><td>#{request.reason}</td></tr>"
              body += "<tr><td><b>CloudForms Provisioning Request ID</b></td><td><a href='https://#{cfme_hostname}/miq_request/show/#{request.id}'>#{request.id}</a></td></tr>"
              body += "</table>"
              body += "<br />"

              # get child request tasks
              request_tasks = request.miq_request_tasks
              log(:info, "request_tasks => #{request_tasks}") if @DEBUG

              # check for any other provision request ids set on the parent task and get those child request tasks
              if !service_task.nil?
                additional_vm_provision_request_ids = service_task.get_option(:provision_request_ids) || {}
                additional_vm_provision_request_ids = additional_vm_provision_request_ids.values
                additional_vm_provision_requests = additional_vm_provision_request_ids.collect {|provision_request_id| @handle.vmdb('miq_request').find_by_id(provision_request_id)}
                request_tasks += additional_vm_provision_requests.collect {|vm_provision_request| vm_provision_request.miq_request_tasks}.flatten
                log(:info, "additional_vm_provision_request_ids => #{additional_vm_provision_request_ids}") if @DEBUG
                log(:info, "additional_vm_provision_requests    => #{additional_vm_provision_requests}") if @DEBUG
                log(:info, "updated request_tasks               => #{request_tasks}") if @DEBUG
              end

              # filter down to only the template request tasks
              vm_tasks = request_tasks.select {|task| task.request_type == 'template'}

              # add vm information
              log(:info, "vm_tasks => #{vm_tasks}") if @DEBUG
              body += "<h1>VMs</h1>"
              body += "<table border=1 cellpadding=5 style='border-collapse: collapse;'>"
              body += "<tr><th><b>Name</b></th><th><b>IP Address(es)</b></th><th><b>State</b></th><th><b>Status</th><th><b>Power</b></th><th><b>CloudForms Provisioning Task ID</b></th><th><b>Last Message</b></tr>"
              vm_tasks.each do |vm_task|
                body += "<tr>"
                vm = vm_task.vm

                # add VM name
                vm_name = vm.name unless vm.nil?
                vm_name ||= vm_task.options[:vm_target_name]
                vm_name ||= 'Unknown'

                body += "<td>"
                unless vm.nil?
                  body += "<a href='https://#{cfme_hostname}/vm_or_template/show/#{vm.id}'>#{vm_name}</a>"
                else
                  body += vm_name
                end
                body += "</td>"

                # add IP addresses
                vm_ip_addresses = vm_task.vm.ipaddresses.join(', ') unless vm.nil?
                vm_ip_addresses ||= 'Unknown'
                body += "<td>#{vm_ip_addresses}</td>"

                # add provisioning request state
                vm_state = vm_task.state.capitalize
                vm_state = 'Cloned (Provisioned)' if state =~ /provisioned/i # Provisioned makes it seem like VM is done being provisioned, so attempt to make it more clear
                body += "<td>#{vm_state}</td>"

                # add provisioning request status
                vm_status = vm_task.statemachine_task_status.capitalize
                if vm_status =~ /error/i
                  vm_status_style = 'color: red'
                else
                  vm_status_style = ''
                end
                body += "<td><span style='#{vm_status_style}'>#{vm_status}</span></td>"

                # add power state
                vm_power_state = vm.power_state.capitalize unless vm.nil?
                vm_power_state ||= 'Unknown'
                body += "<td>#{vm_power_state}</td>"

                # add task id
                body += "<td>#{vm_task.id}</td>"

                # add last task message
                body += "<td>#{CGI::escapeHTML(vm_task.message)}</td>"

                body += "</tr>"
              end
              body += "</table>"
              body += "<br />"

              # append telemetry data to email if any exists
              unless service.nil?
                service_telemetry_custom_keys = service.custom_keys.select {|custom_key| custom_key =~ /#{PROVISIONING_TELEMETRY_PREFIX}/}
                unless service_telemetry_custom_keys.empty?
                  body += "<h1>Service Provisioning Statistics</h1>"
                  body += "<table border=1 cellpadding=5 style='border-collapse: collapse;'>"
                  service_telemetry_custom_keys.each do |custom_key|
                    body += "<tr><td><b>#{custom_key}</b></td><td>#{service.custom_get(custom_key)}</td></tr>"
                  end
                  body += "</table>"
                end
              end

              # Send email
              log("info", "Sending email to <#{to}> from <#{from}> subject: <#{subject}>") if @DEBUG
              log("info", "Sending email body: #{body}") if @DEBUG
              @handle.execute(:send_email, to, from, subject, body)

              log('info', "END: send_service_provision_update_email") if @DEBUG
            end

          end
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  RedHatConsulting_Utilities::Automate::Service::Provisioning::Email::ServiceProvision_Update.new.main()
end
