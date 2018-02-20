# Suported VMDB Objects
#   * ext_management_system
#   * ems_cluster
#   * host
#
# Parameters
#   $evm.root['vmdb_object_type']
#   $evm.root['dialog_tag_category']
#   $evm.root['dialog_lans']
#
@DEBUG = true

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
  
  # get the host(s) that the LANs are associated with that need to be tagged
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
  $evm.log(:info, "hosts => #{hosts}") if @DEBUG
  
  # get the parameters
  tag_category = $evm.root['dialog_tag_category']
  lan_names    = $evm.root['dialog_lan_names']
  $evm.log(:info, "tag_category => #{tag_category}") if @DEBUG
  $evm.log(:info, "lan_names    => #{lan_names}")    if @DEBUG
  
  shared_only = $evm.inputs['shared_only']
  if shared_only
    # find the LANs by name or id
    selected_lans_to_hosts = {}
    hosts.each do |host|
      host.lans.each do |lan|
        selected_lans_to_hosts[lan] = host if lan_names.include?(lan.name) || lan_names.include?(lan.id)
      end
    end
    $evm.log(:info, "selected_lans_to_hosts => #{selected_lans_to_hosts}") if @DEBUG
    
    # get all the tags that selected LANs are tagged with
    all_lan_tags = []
    selected_lans_to_hosts.each { |lan, host| all_lan_tags += lan.tags }
    all_lan_tags.uniq!
    $evm.log(:info, "all_lan_tags => #{all_lan_tags}") if @DEBUG

    # find the tags shared by all selected LANs
    shared_lan_tags = all_lan_tags.select do |lan_tag|
      tag_category, tag_name = lan_tag.split('/')
      selected_lans_to_hosts.all? { |lan, host| lan.tagged_with?(tag_category, tag_name) }
    end
    $evm.log(:info, "shared_lan_tags => #{shared_lan_tags}") if @DEBUG
    
    # find the tag category and tag descriptions to create a pretty value
    value = shared_lan_tags.collect do |lan_tag_category_and_tag_name|
      tag = $evm.vmdb(:classification).find_by_name(lan_tag_category_and_tag_name)
      "#{tag.parent.description}: #{tag.description}"
    end
  else
    # sort the lans by provider and host
    lans_by_host_by_provider = {}
    hosts.each do |host|
      host.lans.each do |lan|
        if lan_names.include?(lan.name) || lan_names.include?(lan.id)
          lans_by_host_by_provider[host.ext_management_system.name]            ||= {}
          lans_by_host_by_provider[host.ext_management_system.name][host.name] ||= []
          lans_by_host_by_provider[host.ext_management_system.name][host.name] << lan 
        end
      end
    end
    
    # create the value to show to the user
    value = []
    INDENT = '        '
    lans_by_host_by_provider.each do |provider, hosts|
      value << "Provider <#{provider}>"
      hosts.each do |host, lans|
        value << "#{INDENT*1}Host <#{host}>"
        lans.each do |lan|
          value << "#{INDENT*2}LAN <#{lan.name} (#{lan.switch.name})>"
          lan.tags.each do |lan_tag_category_and_tag_name|
            tag = $evm.vmdb(:classification).find_by_name(lan_tag_category_and_tag_name)
            value << "#{INDENT*3}Tag <#{tag.parent.description}: #{tag.description}>"
          end
        end
      end
    end
  end
  
  $evm.log(:info, "value => #{value}") if @DEBUG
  
  # create the dialog field
  dialog_field = $evm.object
  dialog_field["sort_by"]    = "value"
  dialog_field["sort_order"] = "ascending"
  dialog_field["data_type"]  = "string"
  dialog_field["value"]      = value.join("\n")
end
