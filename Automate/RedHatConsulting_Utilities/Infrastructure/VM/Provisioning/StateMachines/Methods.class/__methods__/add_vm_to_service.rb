# Adds the given VM to service specified on the provision request.
#
# EXPECTED
#   EVM ROOT
#     miq_provision - VM Provisining request contianing the VM to add to a service
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

begin
  # Get provisioning object
  prov = $evm.root['miq_provision']
  error('Provisioning request not found') if prov.nil?
  $evm.log(:info, "Provision:<#{prov.id}> Request:<#{prov.miq_provision_request.id}> Type:<#{prov.type}>")
  $evm.log(:info, "$evm.root['miq_provision'].attributes => {")         if @DEBUG
  prov.attributes.sort.each { |k,v| $evm.log(:info, "\t#{k} => #{v}") } if @DEBUG
  $evm.log(:info, "}")                                                  if @DEBUG
  
  # get the VM
  vm = prov.vm
  error('VM on provisining request not found') if vm.nil?
  $evm.log(:info, "vm = #{vm}") if @DEBUG
  
  # get the service
  ws_values  = prov.options[:ws_values]
  service_id = ws_values[:service_id]
  if service_id
    service = $evm.vmdb('service').find_by_id(service_id)
  
    # add the VM to the service
    vm.add_to_service(service)
    $evm.log(:info, "Added VM to service: { :vm => '#{vm.name}', :service => '#{service.name}', :service_id => '#{service.id}' }")
  else
    $evm.log(:warn, "ID of Service to add VM to not found.")
  end
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  $evm.root['ae_result'] = 'error'
end
