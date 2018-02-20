# Tags a given set of LANs associated with currently selected VMDB object with a given set of tags
#
# Parameters
#   $evm.root['dialog_tag_category']
#   $evm.root['dialog_multiselect_tags']
#   $evm.root['dialog_single_value_tag']
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
  
  # get the parameters
  tag_category           = $evm.root['dialog_tag_category']
  multi_select_tag_names = $evm.root['dialog_multiselect_tags'] # could have selected multiple
  single_value_tag_name  = $evm.root['dialog_single_value_tag']  # could have selected one
  lan_names              = $evm.root['dialog_lan_names']
  $evm.log(:info, "tag_category           => #{tag_category}")           if @DEBUG
  $evm.log(:info, "multi_select_tag_names => #{multi_select_tag_names}") if @DEBUG
  $evm.log(:info, "single_value_tag_name  => #{single_value_tag_name}")  if @DEBUG
  $evm.log(:info, "lan_names    => #{lan_names}")                        if @DEBUG
  
  # find the lans by name or id
  selected_lans_to_hosts = {}
  hosts.each do |host|
    host.lans.each do |lan|
      selected_lans_to_hosts[lan] = host if lan_names.include?(lan.name) || lan_names.include?(lan.id)
    end
  end
  $evm.log(:info, "selected_lans_to_hosts => #{selected_lans_to_hosts}") if @DEBUG
  
  # create the new_tags list
  # NOTE: this is a bit of a cheat in that really only single_value_tag_name or multi_select_tag_names should have values
  #       and this could be verified against the selected tag category. But being lazy and just makeing assumptions that
  #       is all already handled before we get here.
  new_tags = []
  new_tags << "#{tag_category}/#{single_value_tag_name}" if !single_value_tag_name.blank?
  multi_select_tag_names.each { |tag_name| new_tags << "#{tag_category}/#{tag_name}" }
  $evm.log(:info, "new_tags => #{new_tags}") if @DEBUG
  
  # tag all the VLANs
  selected_lans_to_hosts.each do |lan, host|
    new_tags.each do |new_tag|
      $evm.log(:info, "Assign Tag <#{new_tag}> to LAN <#{lan.name}> on Host <#{host.name}> on Provider <#{host.ext_management_system.name}>") if @DEBUG
      tag_category, tag_name = new_tag.split('/')
      already_assigned = lan.tagged_with?(tag_category, tag_name)
      $evm.log(:info, "tag_category     => #{tag_category}")     if @DEBUG
      $evm.log(:info, "tag_name         => #{tag_name}")         if @DEBUG
      $evm.log(:info, "already_assigned => #{already_assigned}") if @DEBUG
      
      # only attempt to tag if not already tagged
      tag = $evm.vmdb(:classification).find_by_name(new_tag)
      if !already_assigned
        # attempt to tag the LAN
        lan.tag_assign(new_tag)
        
        # verify the LAN is now tagged
        now_assigned = lan.tagged_with?(tag_category, tag_name)
        $evm.log(:info, "now_assigned => #{now_assigned}") if @DEBUG
        
        # send message
        if now_assigned
          message = "Tag <#{tag.parent.description}: #{tag.description}> has been assigned to " +
                    "LAN <#{lan.name} (#{lan.switch.name})> " +
                    "on Host <#{host.name}> " +
                    "on Provider <#{host.ext_management_system.name}>"
          $evm.create_notification(:level => 'info', :message => message)
          $evm.log(:info, message)
        else
          message = "Tag <#{tag.parent.description}: #{tag.description}> failed to be assigned to " +
                    "LAN <#{lan.name} (#{lan.switch.name})> " +
                    "on Host <#{host.name}> " +
                    "on Provider <#{host.ext_management_system.name}>"
          $evm.create_notification(:level => 'error', :message => message)
          $evm.log(:error, message)
        end
      else
        message = "Tag <#{tag.parent.description}: #{tag.description}> already assigned to " +
                  "LAN <#{lan.name} (#{lan.switch.name})> " +
                  "on Host <#{host.name}> " +
                  "on Provider <#{host.ext_management_system.name}>"
        $evm.log(:info, message)
      end
    end
  end
rescue => error
  message = "Unexpected error tagging LANs. See log for more details. #{error}"
  $evm.create_notification(:level => 'error', :message => message)
  error(message + "\n#{error.backtrace.join("\n")}")
end
