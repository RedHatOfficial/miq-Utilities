# Filter clusters, hosts, and datastores based on tags
# The only expected output from this method is a hash of tags. Each tag name can be mapped to either a single value or an array
# If a single value is passed for a tag, that value must be matched on a resource for it to be selected during placement
# If an array of values is passed, any one of those values must match on a resource
#
# NOTE: Intended to be overriden by implementers.
#
# SETS
#   EVM OBJECT
#     'placement_filters' - Hash of tag names to values that must exist for a resource to be selected in the placement process
@DEBUG = false

# IMPLEMENTERS: Update with business logic
# @return hash of tags to values
def get_placement_filters
  prov = $evm.root["miq_provision"]
  user = prov.miq_request.requester
  error("User not specified") if user.nil?
  normalized_ldap_group = user.normalized_ldap_group.gsub(/\W/,'_')

  #By default, look for either prov_scope all or equal to the requesting user's ldap group
  filters = {"prov_scope"=>["all",normalized_ldap_group]}
  
  return filters
end

# IMPLEMENTERS: DO NOT MODIFY
#
# Log an error and exit.
#
# @param msg Message to error with
def error(msg)
  $evm.log(:error, msg)
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = msg.to_s
  exit MIQ_STOP
end

# IMPLEMENTERS: DO NOT MODIFY
#
# Set the filters on $evm.object
begin
  placement_filters = get_placement_filters
  $evm.log(:info, "Setting placement filters to "+placement_filters.to_s) if @DEBUG    
  
  $evm.object['placement_filters'] = placement_filters
end
