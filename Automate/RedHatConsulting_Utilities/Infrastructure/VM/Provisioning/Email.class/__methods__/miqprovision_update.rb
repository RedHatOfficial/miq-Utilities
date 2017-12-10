# Sends an email with an update about the given provisioning task
#
# PARAMETERS
#   root
#     miq_provision - Provisioning task to send the update about. 
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

# From a given MiqProvision and parameters in the environment determine the email addresses to send emails to.
#
# @param prov MiqProvision to send email about
#
# @return array of email addresses to send meail to
def determine_to_email_addresses(prov)
  owner_email = prov.options[:owner_email]
  $evm.log(:warn, "Provision owner email is nil") if owner_email.nil?

  # get additional to email addresses
  additional_to_email_addresses = get_param(:additional_to_email_addresses)
  $evm.log(:info, "additional_to_email_addresses => #{additional_to_email_addresses}") if @DEBUG
  
  # determine to email addresses
  to_email_addresses = []
  to_email_addresses.push(owner_email)                unless owner_email.nil?
  to_email_addresses += additional_to_email_addresses unless additional_to_email_addresses.nil?
  
  $evm.log(:info, "to_email_addresses => #{to_email_addresses}") if @DEBUG
  return to_email_addresses
end

# Sends an email with a provisioning update.
#
# @param prov                     MiqProvision to send the update about
# @param updated_message          The provisioning update message
# @param current_provision_result The current provision result
def send_vm_provision_update_email(prov, updated_message, current_provision_result)
  vm = prov.vm
  
  to_email_addresses = determine_to_email_addresses(prov)
  if !to_email_addresses.empty?
    # create to email address(es)
    to = to_email_addresses.join(';')
    
    # create from email address
    from = get_param(:from_email_address)

    # get appliance
    appliance   = $evm.object['appliance']
    appliance ||= $evm.root['miq_server'].hostname
    
    # get vm name
    vm_name = 'unknown'
    if vm
      vm_name = vm.name
    elsif prov.options[:vm_target_name]
      vm_name = prov.options[:vm_target_name]
    end
    
    # determine subject and status
    
    if current_provision_result == "error"
      subject = "VM Provision Errored - #{vm_name}"
      status  = "<span style='color: red'>#{current_provision_result}</span>"
    else
      subject = "VM Provision Update - #{vm_name}"
      status  = current_provision_result
    end
      
    # create body
    body = ""
    body += "<h1>VM</h1>"
    body += "<table border=1 cellpadding=5 style='border-collapse: collapse;'>"
    if vm
      body += "<tr><td><b>Name</b></td><td><a href='https://#{appliance}/vm_or_template/show/#{vm.id}'>#{vm_name}</a></td></tr>"
    else
      body += "<tr><td><b>Name</b></td><td>#{vm_name}</td></tr>"
    end
    body += "<tr><td><b>Request</b></td><td>#{prov.miq_request_id}</td></tr>"
    body += "<tr><td><b>IPs</b></td><td>#{vm.ipaddresses.join(', ')}</td></tr>" unless vm.nil? || vm.ipaddresses.empty?
    body += "<tr><td><b>Status</b></td><td>#{status}</td></tr>"
    body += "<tr><td><b>Message</b></td><td>#{updated_message}</td></tr>"
    body += "</table>"
    body += "</br>"
  
    $evm.log("info", "Sending email to <#{to}> from <#{from}> subject: <#{subject}>")
    $evm.execute('send_email', to, from, subject, body)
  else
    $evm.log(:warn, "No owner or additional to email addresses specified to send error email to. Skipping email.")
  end
end

begin
  # get the provisioning task
  prov = $evm.root['miq_provision']
  $evm.log(:info, "Provision:<#{prov.id}> Request:<#{prov.miq_provision_request.id}> Type:<#{prov.type}>") if @DEBUG
  $evm.log(:info, "prov.attributes => {")                               if @DEBUG
  prov.attributes.sort.each { |k,v| $evm.log(:info, "\t#{k} => #{v}") } if @DEBUG
  $evm.log(:info, "}")                                                  if @DEBUG
  error("miq_provision object not provided") unless prov
  
  # get the VM provision update message
  update_message   = get_param(:vm_provision_update_message)
  update_message ||= prov.miq_request.user_message
  
  # get the current VM provision result
  vm_current_provision_result = get_param(:vm_current_provision_result)
  
  # send the email
  send_vm_provision_update_email(prov, update_message, vm_current_provision_result)
end
