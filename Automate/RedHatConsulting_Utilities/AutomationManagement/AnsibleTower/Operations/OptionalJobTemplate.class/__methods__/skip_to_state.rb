# Helper method used to skip to a given state.
# Great for error or exception handling.
#
# EXPECTED
#   INPUT PARAMETERS
#     next_state - The next state to skip to
#
@DEBUG = false

begin
  # set the tags and attributes for the LDAP sync failure
  next_state = $evm.inputs['next_state']

  # depending on if this method was entered by on_error or on_exit
  # the new result needs to be updated correctly
  case $evm.root['ae_status_state']
    when 'on_error'
      new_result = 'continue'
    when 'on_exit'
      new_result = 'skip'
    else
      new_result = 'skip'
  end
  $evm.log(:info, "{ $evm.root['ae_status_state'] => #{$evm.root['ae_status_state']}, $evm.root['ae_result'] => #{$evm.root['ae_result']}, new_result => #{new_result} }") if @DEBUG
  
  # Set attributes to skip to specified next state
  $evm.log(:info, "Skip to State: #{next_state}")
  $evm.root['ae_result']     = new_result
  $evm.root['ae_next_state'] = next_state
end
