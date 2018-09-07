#
# Description: This method sends out retirement emails when the following events are raised:
# Events: vm_retire_warn, vm_retired, vm_entered_retirement
# Model Notes:
# 1. to_email_address - used to specify an email address in the case where the
#    vm's owner does not have an  email address. To specify more than one email
#    address separate email address with commas. (I.e. admin@example.com,user@example.com)
# 2. from_email_address - used to specify an email address in the event the
#    requester replies to the email
# 3. signature - used to stamp the email with a custom signature
#
@DEBUG = false

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
# @param vm VM to determine the to email addresses for
#
# @return array of email addresses to send the email to
def determine_to_email_addresses(vm)
  to_email_addresses = []
  
  # get owner email
  owner         = vm.owner    unless vm.nil?
  owner_email   = owner.email unless owner.nil?
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

begin

  # Look in the current object for a VM
  vm = $evm.object['vm']
  if vm.nil?
    vm_id = $evm.object['vm_id'].to_i
    vm = $evm.vmdb('vm', vm_id) unless vm_id == 0
  end

  # Look in the Root Object for a VM
  if vm.nil?
    vm = $evm.root['vm']
    if vm.nil?
      vm_id = $evm.root['vm_id'].to_i
      vm = $evm.vmdb('vm', vm_id) unless vm_id == 0
    end
  end

  # Look in the Root Object for a Provision/Request
  prov = $evm.root['miq_provision_request'] || $evm.root['miq_provision']
  vm = prov.vm if prov && vm.nil?

  raise "User not specified" if vm.nil?

  # Get VM Name
  vm_name = vm['name']

  # Look at the Event Type in the Current Object or in the Root Object
  event_type = $evm.object['event'] || $evm.root['event_type']

  # determine to email addresses
  to_email_addresses = determine_to_email_addresses(vm)
  to_email_addresses = to_email_addresses.join(';')

  # determine the CFME/ManageIQ hostname
  cfme_hostname = determine_cfme_hostname()
  
  # determine from email address
  from_email_address = determine_from_email_address(cfme_hostname)

  ######################################
  #
  # VM Retirement Warning Email
  #
  ######################################
  if event_type == "vm_retire_warn"
    # email subject
    subject = "VM Retirement Warning for #{vm_name}"

    # Build email body
    body = "Hello, "
    body += "<br><br>Your virtual machine: [#{vm_name}] will be retired on [#{vm['retires_on']}]."
    body += "<br><br>If you need to use this virtual machine past this date please request"
    body += "<br><br>an extension by contacting Support."
  end

  ######################################
  #
  # VM Retirement Exended Email
  #
  ######################################
  if event_type == "vm_retire_extend"
    # email subject
    subject = "VM Retirement Extended for #{vm_name}"

    # Build email body
    body = "Hello, "
    body += "<br><br>Your virtual machine: [#{vm_name}] will now be retired on [#{vm['retires_on']}]."
    body += "<br><br>If you need to use this virtual machine past this date please request"
    body += "<br><br>an extension by contacting Support."
  end

  ######################################
  #
  # VM has entered Retirement Email
  #
  ######################################
  if event_type == "vm_entered_retirement"
    # email subject
    subject = "VM #{vm_name} has entered retirement"

    # Build email body
    body = "Hello, "
    body += "<br><br>Your virtual machine named [#{vm_name}] has been retired."
    body += "<br><br>You will have up to 3 days to un-retire this VM. Afterwhich time the VM will be deleted."
  end

  ######################################
  #
  #  VM Retirement Email
  #
  ######################################
  if event_type == "vm_retired"
    # email subject
    subject = "VM Retirement Completed - #{vm_name}"
    
    released_ip_address = get_param(:released_ip_address)
    if !released_ip_address
      released_ip_address = "None"
    end

    # Build email body
    body = ""
    body += "<h1>VM</h1>"
    body += "<table border=1 cellpadding=5 style='border-collapse: collapse;'>"
    body += "<tr><td><b>Name</b></td><td><a href='https://#{cfme_hostname}/vm_or_template/show/#{vm.id}'>#{vm.name}</a></td></tr>"
    body += "<tr><td><b>Released IP</b></td><td>#{released_ip_address}</td></tr>"
    body += "<tr><td><b>Status</b></td><td>Retired</td></tr>"
    body += "</table>"
    body += "</br>"
  end

  $evm.log("info", "Sending email to <#{to_email_addresses}> from <#{from_email_address}> subject: <#{subject}>") if @DEBUG
  $evm.log("info", "Sending email body: #{body}")                                                                 if @DEBUG
  $evm.execute('send_email', to_email_addresses, from_email_address, subject, body)
end
