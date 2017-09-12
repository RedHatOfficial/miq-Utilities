# This method is used to email the provision requester that
# the Service provisioning request has been approved
#
# Events: request_approved
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
#  Request			10000000000373
#  Status			Approved
#  Approver Notes	Auto-Approved
#
# -----------
def send_service_provision_approved_email(request, to, from, appliance)
  $evm.log('info', "START: send_service_provision_approved_email") if @DEBUG

  # Build subject
  subject = "Service Provision Approved - #{request.id}"

  # build the body
  body = ""
  body += "<h1>Service</h1>"
  body += "<table border=1 cellpadding=5 style='border-collapse: collapse;'>"
  body += "<tr><td><b>Request</b></td><td><a href='https://#{appliance}/miq_request/show/#{request.id}'>#{request.id}</a></td></tr>"
  body += "<tr><td><b>Status</b></td><td>Approved</td></tr>"
  body += "<tr><td><b>Approver Notes</b></td><td>#{request.reason}</td></tr>"
  body += "</table>"

  # Send email
  $evm.log("info", "Sending email to <#{to}> from <#{from}> subject: <#{subject}>") if @DEBUG
  $evm.log("info", "Sending email body: #{body}")                                   if @DEBUG
  $evm.execute(:send_email, to, from, subject, body)
  
  $evm.log('info', "END: send_service_provision_approved_email") if @DEBUG
end

begin
  # get the request
  request     = $evm.root['miq_request']
  error("miq_request not set") if request.nil?
  
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
  $evm.create_notification(:level => 'warning', :message => "No Requestor or Owner email address(es) to send service provision approved notification to. [#{request.id}]") if to.blank?
  
  # Get from_email_address from model
  from = $evm.object['from_email_address']
  error("from_email_address not found") if from.blank?
  
  # get appliance
  appliance   = $evm.object['appliance']
  appliance ||= $evm.root['miq_server'].hostname
  
  # send the email
  send_service_provision_approved_email(request, to, from, appliance)
end
