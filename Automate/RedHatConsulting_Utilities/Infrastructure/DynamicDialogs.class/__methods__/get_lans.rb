# Get all LANs associated with the given VMDB Object for use in a dynamic dialog.
# Either returns them listed with the LAN name as the key or or the LAN id as the name.
#
# Suported VMDB Objects
#   * ext_management_system
#   * ems_cluster
#   * host
#
# Parameters
#   $evm.root['vmdb_object_type']
#   $evm.inputs['values_key']
#   
@DEBUG = false

def dump_object(object_string, object)
  $evm.log("info", "Listing #{object_string} Attributes:") 
  object.attributes.sort.each { |k, v| $evm.log("info", "\t#{k}: #{v}") }
  $evm.log("info", "===========================================") 
end

def dump_current
  $evm.log("info", "Listing Current Object Attributes:") 
  $evm.current.attributes.sort.each { |k, v| $evm.log("info", "\t#{k}: #{v}") }
  $evm.log("info", "===========================================") 
end

def dump_root
  $evm.log("info", "Listing Root Object Attributes:") 
  $evm.root.attributes.sort.each { |k, v| $evm.log("info", "\t#{k}: #{v}") }
  $evm.log("info", "===========================================") 
end

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
  dump_root()    if @DEBUG
  dump_current() if @DEBUG
  
  # If there isn't a vmdb_object_type yet just exit. The method will be recalled with an vmdb_object_type
  exit MIQ_OK unless $evm.root['vmdb_object_type']
  
  # get the hosts that have associated LANs to list
  vmdb_object_type = $evm.root['vmdb_object_type']
  case vmdb_object_type
    when 'ext_management_system'
      ems = $evm.root['ext_management_system']
      $evm.log(:info, "ems=#{ems.name}") if @DEBUG
    
      hosts = ems.hosts
    when 'ems_cluster'
      cluster = $evm.root['ems_cluster']
      $evm.log(:info, "cluster=#{cluster.name}") if @DEBUG
    
      hosts = cluster.hosts
    when 'host'
      host = $evm.root['host']
      $evm.log(:info, "host=#{host.name}") if @DEBUG
    
      hosts = [host]
    else
      error("$evm.root['vmdb_object_type']=#{$evm.root['vmdb_object_type']} is not one of expected ['ext_management_system', 'ems_cluster', 'host'].")
  end
  
  # determine how to list the LANs
  values_key = $evm.inputs['values_key']
  error("values_key parameter <#{valules_key}> must be one of ['name', 'id'].") if !['name', 'id'].include?(values_key)
  
  # create the LANs values
  lans = {}
  hosts.each do |host|
    host.lans.each do |lan|
      case values_key
        when 'name'
          lans[lan.name] = "#{lan.name} (#{lan.switch.name}) (#{host.ext_management_system.name})"
        when 'id'
          lans[lan.id] = "#{lan.name} (#{lan.switch.name}) (#{host.name}) (#{host.ext_management_system.name})"
      end
    end
  end
  
  # create the dialog field
  dialog_field = $evm.object
  dialog_field["sort_by"]    = "value"
  dialog_field["sort_order"] = "ascending"
  dialog_field["data_type"]  = "integer"
  dialog_field["values"]     = lans
  
  $evm.log(:info, "lans => #{lans}") if @DEBUG
end
