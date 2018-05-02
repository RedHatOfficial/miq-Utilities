#
# Description: This method checks to see if the service has been provisioned
#
@DEBUG = false

$evm.log("info", "Listing Root Object Attributes:")
$evm.root.attributes.sort.each { |k, v| $evm.log("info", "\t#{k}: #{v}") }
$evm.log("info", "===========================================")

# Get current provisioning status
task        = $evm.root['service_template_provision_task']
task_status = task['status']
result      = task.statemachine_task_status

$evm.log('info', "Service Provision Check returned <#{result}> for state <#{task.state}> and status <#{task_status}>")


if result == 'ok' || result == 'retry'
  # assume ready to move on
  new_result = 'ok'
  
  # need to retry because of sub tasks?
  if task.miq_request_tasks.any? { |t| t.state != 'finished' }
    new_result = 'retry'
    $evm.log('info', "Child tasks not finished. Setting retry for task: #{task.id} ")
  end
  
  # need to retry because of sub provision requests?
  # check for any provision requests set and wait for those to finish
  provision_request_ids = task.get_option(:provision_request_ids) || {}
  provision_request_ids = provision_request_ids.values
  $evm.log(:info, "provision_request_ids => #{provision_request_ids}") if @DEBUG
  $evm.log(:info, "Child provision requests states <#{provision_request_ids.collect { |provision_request_id| $evm.vmdb('miq_request').find_by_id(provision_request_id).state }}>") if @DEBUG
  if provision_request_ids.any? { |provision_request_id| $evm.vmdb('miq_request').find_by_id(provision_request_id).state != 'finished' }
    new_result = 'retry'
    $evm.log('info', "Child provision requests not finished. Setting restult <#{result}> for task: #{task.id} ")
  end
  
  result = new_result
end

case result
when 'error'
  $evm.root['ae_result'] = 'error'
  reason = $evm.root['service_template_provision_task'].message
  reason = reason[7..-1] if reason[0..6] == 'Error: '
  $evm.root['ae_reason'] = reason
when 'retry'
  $evm.root['ae_result']         = 'retry'
  $evm.root['ae_retry_interval'] = '1.minute'
when 'ok'
  # Bump State
  $evm.root['ae_result'] = 'ok'
end
