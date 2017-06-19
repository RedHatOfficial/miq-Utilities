# Sends an email when the service finishes provisioning.
#
@DEBUG = false

# Log an error and exit.
#
# @param msg Message to error with
def error(msg)
  $evm.log(:error, msg)
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = msg.to_s
  exit MIQ_STOP
end

# Sends an email about the service that was just provisioned:
#
# EXAMPLE:
# -----------
#  Service
#
#  Service	Email Test 3
#  Request	10000000000373
#  Status	Provisioned
#
#  VMs
#
#  VM Name	IP Address(es)
#  cfme-self-service0005.rhc-lab.iad.redhat.com	10.15.69.128
#  cfme-self-service0006.rhc-lab.iad.redhat.com	10.15.69.129
# -----------
def send_service_provision_complete_email(request, service, to, from)
  $evm.log('info', "START: send_service_provision_complete_email") if @DEBUG

  # Build subject
  subject = "Service Provision Completed - #{service.name} (#{request.id})"
  
  # build the body
  body = ""
  body += "<h1>Service</h1>"
  body += "<table border=1 cellpadding=5 style='border-collapse: collapse;'>"
  body += "<tr><td><b>Service</b></td><td>#{service.name}</td></tr>"
  body += "<tr><td><b>Request</b></td><td>#{request.id}</td></tr>"
  body += "<tr><td><b>Status</b></td><td>Provisioned</td></tr>"
  body += "</table>"
  body += "</br>"
  
  body += "<h1>VMs</h1>"
  body += "<table border=1 cellpadding=5 style='border-collapse: collapse;'>"
  body += "<tr><th><b>VM Name</b></th><th><b>IP Address(es)</b></th></tr>"
  service.vms.each do |vm|
    body += "<tr><td>#{vm.name}</td><td>#{vm.ipaddresses.join(', ')}</td></tr>"
  end
  body += "</table>"

  # Send email
  $evm.log("info", "Sending email to <#{to}> from <#{from}> subject: <#{subject}>")
  $evm.log("info", "Sending email body: #{body}") if @DEBUG
  $evm.execute(:send_email, to, from, subject, body)
  
  $evm.log('info', "END: send_service_provision_complete_email") if @DEBUG
end

begin
  # get service task, request, destination
  task        = $evm.root['service_template_provision_task']
  error("service_template_provision_task not set") if task.nil?
  request     = task.miq_request
  destination = task.destination
  
  # determine destiation email
  requester       = request.requester
  requester_email = requester.email || nil
  owner_email     = request.options[:owner_email] || nil
  $evm.log(:info, "Requester email:<#{requester_email}> Owner Email:<#{owner_email}>") if @DEBUG
  to = ''
  if !requester_email.nil?
    to += "#{requester_email};"
  end
  if !owner_email.nil?
    to += "#{owner_email};"
  end  
  error("No Requestor or Owner email address(es) found to send service provision complete email to.") if to.blank?
  
  # Get from_email_address from model
  from = $evm.object['from_email_address']
  error("No from email address configured for sending service provsiion complete email from.") if from.blank?
  
  # send the email
  send_service_provision_complete_email(request, destination, to, from)
end
