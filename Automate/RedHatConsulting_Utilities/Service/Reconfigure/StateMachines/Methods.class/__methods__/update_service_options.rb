# Updates service options after a re-configure
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

def dump_root
  $evm.log("info", "Listing Root Object Attributes:") 
  $evm.root.attributes.sort.each { |k, v| $evm.log("info", "\t#{k}: #{v}") }
  $evm.log("info", "===========================================") 
end

def dump_object(object_string, object)
  $evm.log("info", "Listing #{object_string} Attributes:") 
  object.attributes.sort.each { |k, v| $evm.log("info", "\t#{k}: #{v}") }
  $evm.log("info", "===========================================") 
end

# Updates the serivce dialog options based on $evm.root dialog options
#
# @param service Update the dialog options of this serivce based on $evm.root dialog options
def update_dialog_options(service)
  $evm.root.attributes.each do |k,v|
    next unless k =~ /^dialog_.*/
    original_value = service.get_dialog_option(k)
    if original_value = v
      $evm.log(:info, "Updating Service <#{service.name}> Option <#{k}>: #{original_value} to #{v}")
      service.set_dialog_option(k, v)
    end
  end
end

begin
  dump_root() if @DEBUG
  
  service_reconfigure_task = $evm.root['service_reconfigure_task']
  dump_task("service_reconfigure_task", service_reconfigure_task) if @DEBUG
  
  service = service_reconfigure_task.source
  update_dialog_options(service)
end
