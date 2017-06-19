#
# Description: Method Used for Logging Entry/Exit of each method
#  - This method gives a clean beginning/ending to each method called from Automate in the logs
# Author: Dustin Scott, Red Hat
#

# set method for unknown time
def set_unknown
  method_time_seconds = 'Unknown'
  method_time_minutes = 'Unknown'
  return [ method_time_seconds, method_time_minutes ]
end

# set variables
parent_instance = $evm.parent rescue nil

if $evm.inputs['bookend_status'] == 'enter'
  enter_time = Time.now
  parent_instance['enter_time'] = enter_time unless parent_instance.nil?
elsif $evm.inputs['bookend_status'] == 'exit'
  if parent_instance.nil?
    method_time_seconds, method_time_minutes = set_unknown
  elsif parent_instance['enter_time'].nil?
    method_time_seconds, method_time_minutes = set_unknown
  else
    method_time_seconds = (Time.now - parent_instance['enter_time']).round(3)
    method_time_minutes = (method_time_seconds / 60).round(3)
  end
else
  method_time_seconds, method_time_minutes = set_unknown
end

# log the bookend
$evm.log(:info, "=====================================================================")
$evm.log(:info, "#{$evm.inputs['bookend_org']} Customization: #{$evm.inputs['bookend_status'].capitalize} #{$evm.inputs['bookend_parent_method']} method")
$evm.log(:info, "Method <#{$evm.inputs['bookend_parent_method']}> Total Execution Time: <#{method_time_seconds} seconds>, <#{method_time_minutes} minutes>") if ($evm.inputs['bookend_status'] == 'exit' && parent_instance)
$evm.log(:info, "=====================================================================")

# exit with MIQ_OK
exit MIQ_OK
