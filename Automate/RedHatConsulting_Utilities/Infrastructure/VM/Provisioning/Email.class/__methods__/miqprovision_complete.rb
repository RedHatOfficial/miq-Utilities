# This method sends an e-mail when the following event is raised:
#   Events: vm_provisioned
#
@DEBUG = true

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
def send_vm_provision_complete_email(vm, to, from, appliance)
  $evm.log('info', "START: send_vm_provision_complete_email") if @DEBUG

  # Build subject
  subject = "VM Provision Completed - #{vm.name}"
  
  # build the body
  body = ""
  body += "<h1>VM</h1>"
  body += "<table border=1 cellpadding=5 style='border-collapse: collapse;'>"
  body += "<tr><td><b>Name</b></td><td><a href='https://#{appliance}/vm_or_template/show/#{vm.id}'>#{vm.name}</a></td></tr>"
  body += "<tr><td>IPs</td><td>#{vm.ipaddresses.join(', ')}</td></tr>"
  body += "<tr><td><b>Status</b></td><td>Provisioned</td></tr>"
  body += "</table>"
  body += "</br>"

  # Send email
  $evm.log("info", "Sending email to <#{to}> from <#{from}> subject: <#{subject}>") if @DEBUG
  $evm.log("info", "Sending email body: #{body}")                                   if @DEBUG
  $evm.execute(:send_email, to, from, subject, body)
  
  $evm.log('info', "END: send_vm_provision_complete_email") if @DEBUG
end

begin
  # Get vm from miq_provision object
  prov = $evm.root['miq_provision']
  vm = prov.vm
  error("VM not found") if vm.nil?
  
  # Get VM Owner Name and Email
  evm_owner_id = vm.attributes['evm_owner_id']
  owner = nil
  owner = $evm.vmdb('user', evm_owner_id) unless evm_owner_id.nil?
  $evm.log("info", "VM Owner: #{owner.inspect}")
  
  # determine destiation email
  to   = nil
  to   = owner.email unless owner.nil?
  to ||= $evm.object['to_email_address']
  $evm.create_notification(:level => 'warning', :message => "No Owner email to send VM provision complete notification to [#{vm.name}]") if to.blank?

  # Get from_email_address from model
  from = $evm.object['from_email_address']
  error("from_email_address not found") if from.blank?
  
  # get appliance
  appliance   = $evm.object['appliance']
  appliance ||= $evm.root['miq_server'].hostname
  
  # send the email
  if !to.blank? && !from.blank?
    send_vm_provision_complete_email(vm, to, from, appliance)
  end
end
