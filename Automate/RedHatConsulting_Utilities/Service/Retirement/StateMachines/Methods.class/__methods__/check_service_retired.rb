#
# Description: This method checks to see that all of the service resources are retired before retiring the service.
#

service = $evm.root['service']
if service.nil?
  $evm.log('error', "Service Object not found")
  exit MIQ_ABORT
end

$evm.log('info', "Checking if all service resources have been retired.")

result = 'ok'

service.service_resources.each do |sr|
  next if sr.resource.nil?
  next unless sr.resource.respond_to?(:retired?)
  $evm.log('info', "Checking if service resource for service: #{service.name} resource ID: #{sr.id} is retired")
  $evm.log(:info, "Resource <#{sr.name}> in Service <#{service.name}> is marked as Retired <#{sr.resource.retired?}> and has Retirment State of <#{sr.resource.retirement_state}>.")
  if sr.resource.retired?
    $evm.log('info', "resource: #{sr.resource.name} is already retired.")
  elsif sr.resource.retirement_state == 'error'
    result = 'error'
    $evm.log(:error, "resource: #{sr.resource.name} had error retiring.")
  else
    result = 'retry'
    $evm.log('info', "resource: #{sr.resource.name} is not retired, setting retry.")
  end
end

$evm.log('info', "Service: #{service.name} Resource retirement check returned <#{result}>")
case result
when 'error'
  $evm.log(:error, "A resource had an issues retiring for service: #{service.name}. ")
  $evm.root['ae_result'] = 'error'
when 'retry'
  $evm.log('info', "Service: #{service.name} resource is not retired, setting retry.")
  $evm.root['ae_result']         = 'retry'
  $evm.root['ae_retry_interval'] = '1.minute'
when 'ok'
  # Bump State
  $evm.log('info', "All resources are retired for service: #{service.name}. ")
  $evm.root['ae_result'] = 'ok'
end
