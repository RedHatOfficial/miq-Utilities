#
# Description: Dumps the root/object attributes
#

begin
  # set variables
  @method = $evm.current_method
  if $evm.inputs['object_type'] == 'root'
    object = $evm.root
    object_string = "\$evm.root"
  elsif $evm.inputs['object_type'] == 'object'
    object = $evm.parent
    object_string = "\$evm.object"
  else
    raise 'Invalied <object_type> specified.  Valid values are <root> or <object>'
  end
  object_name = object_string.split('.').last.capitalize

  # log all root/object attributes
  $evm.log(:info, "#{object_name}:<#{object_string}> Begin #{object_string}.attributes")
  object.attributes.sort.each { |k, v| $evm.log(:info, "#{object_name}:<#{object_string}> Attribute - #{k}: #{v}") }
  $evm.log(:info, "#{object_name}:<#{object_string}> End #{object_string}.attributes")
  $evm.log(:info, "")

  # exit with MIQ_OK
  exit MIQ_OK
raise
  # set error message
  message = "Error dumping attributes: #{err}"
  
  # log what we failed
  $evm.log(:error, message)
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
        
  # exit with MIQ_WARN status
  exit MIQ_WARN
end
