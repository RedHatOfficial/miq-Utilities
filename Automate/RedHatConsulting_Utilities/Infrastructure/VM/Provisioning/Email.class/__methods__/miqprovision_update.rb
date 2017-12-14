# Sends an email with an update about the vm provisioning request.
#
# Designed to be called from any of the `Infrastructure/VM/Provisioning/Email`
# instances to standerdize what email updates look like.
#
@DEBUG = false

PROVISIONING_TELEMETRY_PREFIX = "Provisioning: Telemetry:"

# Log an error and exit.
#
# @param msg Message to error with
def error(msg)
  $evm.log(:error, msg)
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = msg.to_s
  exit MIQ_STOP
end

# There are many ways to attempt to pass parameters in Automate.
# This function checks all of them in priorty order as well as checking for symbol or string.
#
# Order:
#   1. Inputs
#   2. Current
#   3. Object
#   4. Root
#   5. State
#
# @return Value for the given parameter or nil if none is found
def get_param(param)  
  # check if inputs has been set for given param
  param_value ||= $evm.inputs[param.to_sym]
  param_value ||= $evm.inputs[param.to_s]
  
  # else check if current has been set for given param
  param_value ||= $evm.current[param.to_sym]
  param_value ||= $evm.current[param.to_s]
 
  # else cehck if current has been set for given param
  param_value ||= $evm.object[param.to_sym]
  param_value ||= $evm.object[param.to_s]
  
  # else check if param on root has been set for given param
  param_value ||= $evm.root[param.to_sym]
  param_value ||= $evm.root[param.to_s]
  
  # check if state has been set for given param
  param_value ||= $evm.get_state_var(param.to_sym)
  param_value ||= $evm.get_state_var(param.to_s)

  $evm.log(:info, "{ '#{param}' => '#{param_value}' }") if @DEBUG
  return param_value
end

# Determine the CFME/ManageIQ hostname
#
# @return CFME/ManageIQ hostname
def determine_cfme_hostname()
  cfme_hostname   = get_param(:cfme_hostname)
  cfme_hostname ||= $evm.object['appliance']
  cfme_hostname ||= $evm.root['miq_server'].hostname
  
  $evm.log(:info, "cfme_hostname => #{cfme_hostname}") if @DEBUG
  return cfme_hostname
end

# Determine the email address to send the email from
#
# @param cfme_hostname CFME/ManageIQ hostname the email is coming from
#
# @return email address to send the email from
def determine_from_email_address(cfme_hostname)
  from_email_address   = get_param(:from_email_address)
  from_email_address ||= "cfme@#{cfme_hostname}"
  
  $evm.log(:info, "from_email_address => #{from_email_address}") if @DEBUG
  return from_email_address
end

# Determin the email addresses to send the email to
#
# @param prov miq_provision to determine the to email addresses for
#
# @return array of email addresses to send the email to
def determine_to_email_addresses(prov)
  to_email_addresses = []
  
  # get requester email
  request         = prov.miq_request
  requester       = request.requester
  requester_email = requester.email
  to_email_addresses.push(requester_email) unless requester_email.nil?
  $evm.log(:info, "requester_email => #{requester_email}") if @DEBUG
  
  # get owner email
  vm            = prov.vm
  owner         = vm.owner    unless vm.nil?
  owner_email   = owner.email unless owner.nil?
  owner_email ||= request.options[:owner_email]
  to_email_addresses.push(owner_email) unless owner_email.nil?
  $evm.log(:info, "owner_email => #{owner_email}") if @DEBUG
  
  # get additional to addresses
  additional_to_email_address = get_param(:to_email_address)
  unless additional_to_email_address.nil?
    additional_to_email_address = additional_to_email_address.split(/[;,\s]+/)
    to_email_addresses += additional_to_email_address
  end
  
  # clean up email address list
  to_email_addresses = to_email_addresses.compact.uniq
  
  $evm.log(:info, "to_email_addresses => #{to_email_addresses}") if @DEBUG
  return to_email_addresses
end

# Sends an email about the VM that was just provisioned:
#
# EXAMPLE:
# -----------
#
#  VM
#  |------------------------------------|-----------------------|
#  | Name								| test000.example.com	|
#  | IPS								| 10.0.0.2				|
#  | Service							| My Service			| # OPTIONAL
#  | State								| Provisioned			|
#  | Status								| Ok					|
#  | Step								| checkprovisioned		| # OPTIONAL
#  | Message                            | Bla bal bal			|
#  | CloudForms Provisioning Request ID	| 10000000000373		|
#  |------------------------------------|-----------------------|
#
#  VM Provisioning Statistics 
#  |----------------------------------------------------|---------------------------|
#  | Telemetry: Provisioning: Duration: VM Provisioning	| 00:15:12					|
#  | Telemetry: Provisioning: Duration: VM Clone		| 00:02:01					|
#  | Telemetry: Provisioning: Time: Request Completed	| 2017-12-10 20:30:24 -0500 |
#  | Telemetry: Provisioning: Time: Request Created		| 2017-12-10 20:13:28 -0500 |
#  |----------------------------------------------------|---------------------------|
#
# -----------
def send_vm_provision_complete_email(prov, to, from, update_message, vm_current_provision_ae_result, cfme_hostname)
  $evm.log('info', "START: send_vm_provision_complete_email") if @DEBUG
  
  state =  prov.state.capitalize
  state = 'Cloned (Provisioned)' if state =~ /provisioned/i # Provisioned makes it seem like VM is done being provisioned, so attempt to make it more clear
  
  status   = vm_current_provision_ae_result # if the current ae_result of the VM provision is provided then use that as the status
                                            # since in an error case the provsioning status would not have been updated yet
  status ||= prov.status
  status   = status.capitalize
  
  # get the VM
  vm = prov.vm
  
  # get vm name
  vm_name   = vm.name unless vm.nil?
  vm_name ||= prov.options[:vm_target_name] unless prov.options[:vm_target_name].nil?
  vm_name ||= 'Unknown'
  
  # Build subject
  $evm.log(:info, "{ $evm.object.name => #{$evm.object.name} }") if @DEBUG
  subject = "VM Provision "
  if status =~ /error/i
    subject += "Error -"
  else
    case $evm.object.name
      when /MiqProvision_Complete/i
        subject += "Complete - "
      when /MiqProvision_Update/i
        subject += "Update - #{state} #{status} - "
      when /MiqProvisionRequest_Approved/i
        subject += "Approved - "
      when /MiqProvisionRequest_Denied/i
        subject += "Denied - "
      when /MiqProvisionRequest_Pending/i
        subject += "Pending - "
      else
        subject += "Update - #{state} #{status} - "
    end
  end
  subject += " #{vm_name} (#{prov.miq_provision_request.id})"
  
  # determine status style
  if status =~ /error/i
    status_style = 'color: red'
  else
    status_style = ''
  end
  
  # build the body
  body = ""
  body += "<h1>VM</h1>"
  body += "<table border=1 cellpadding=5 style='border-collapse: collapse;'>"
  unless vm.nil?
    body += "<tr><td><b>Name</b></td><td><a href='https://#{cfme_hostname}/vm_or_template/show/#{vm.id}'>#{vm_name}</a></td></tr>"
  else
    body += "<tr><td><b>Name</b></td><td>#{vm_name}</td></tr>"
  end
  body += "<tr><td><b>IPs</b></td><td>#{vm.ipaddresses.join(', ') unless vm.nil?}</td></tr>"
  body += "<tr><td><b>Service</b></td><td><a href='https://#{cfme_hostname}/service/explorer/s-#{vm.service.id}'>#{vm.service.name}</a></td></tr>" unless vm.nil? || vm.service.nil?
  body += "<tr><td><b>State</b></td><td>#{state}</td></tr>"
  body += "<tr><td><b>Status</b></td><td><span style='#{status_style}'>#{status}</span></td></tr>"
  body += "<tr><td><b>Step</b></td><td>#{$evm.root['ae_state']}</td></tr>" unless $evm.root['ae_state'].nil?
  body += "<tr><td><b>Message</b></td><td>#{update_message}</td></tr>"
  body += "<tr><td><b>CloudForms Provisioning Request ID</b></td><td><a href='https://#{cfme_hostname}/miq_request/show/#{prov.miq_provision_request.id}'>#{prov.miq_provision_request.id}</a></td></tr>"
  body += "</table>"
  body += "<br />"
  
  # append telemetry data to email if any exists
  vm_telemetry_custom_keys = vm.custom_keys.select { |custom_key| custom_key =~ /#{PROVISIONING_TELEMETRY_PREFIX}/ } unless vm.nil?
  unless vm_telemetry_custom_keys.nil? || vm_telemetry_custom_keys.empty?
    body += "<h1>VM Provisioning Statistics</h1>"
    body += "<table border=1 cellpadding=5 style='border-collapse: collapse;'>"
    vm_telemetry_custom_keys.each do |custom_key|
      body += "<tr><td><b>#{custom_key}</b></td><td>#{vm.custom_get(custom_key)}</td></tr>"
    end 
    body += "</table>"
  end

  # Send email
  $evm.log("info", "Sending email to <#{to}> from <#{from}> subject: <#{subject}>") if @DEBUG
  $evm.log("info", "Sending email body: #{body}")                                   if @DEBUG
  $evm.execute(:send_email, to, from, subject, body)
  
  $evm.log('info', "END: send_vm_provision_complete_email") if @DEBUG
end

begin
  # get the miq_provision task
  prov = $evm.root['miq_provision']
  $evm.log(:info, "Provision:<#{prov.id}> Request:<#{prov.miq_provision_request.id}> Type:<#{prov.type}>") if @DEBUG
  $evm.log(:info, "prov.attributes => {")                               if @DEBUG
  prov.attributes.sort.each { |k,v| $evm.log(:info, "\t#{k} => #{v}") } if @DEBUG
  $evm.log(:info, "}")                                                  if @DEBUG
  error("miq_provision object not provided") unless prov

  # determine to email addresses
  to_email_addresses = determine_to_email_addresses(prov)
  to_email_addresses = to_email_addresses.join(';')

  # determine the CFME/ManageIQ hostname
  cfme_hostname = determine_cfme_hostname()
  
  # determine from email address
  from_email_address = determine_from_email_address(cfme_hostname)
  
  # get the VM provision update message
  update_message   = get_param(:vm_provision_update_message)
  update_message ||= prov.miq_request.try(:user_message)
  update_message ||= 'None'
  
  # get current VM provisioning status
  vm_current_provision_ae_result = get_param(:vm_current_provision_ae_result)
  
  # send the email
  unless to_email_addresses.blank?
    send_vm_provision_complete_email(prov, to_email_addresses, from_email_address, update_message, vm_current_provision_ae_result, cfme_hostname)
  else
    warn_message = "No one to send VM Provision Update email to. Request: #{prov.miq_provision_request.id}"
    $evm.log(:warn, warn_message)
    $evm.create_notification(:level   => 'warning',
                             :message => warn_message)
  end
end
