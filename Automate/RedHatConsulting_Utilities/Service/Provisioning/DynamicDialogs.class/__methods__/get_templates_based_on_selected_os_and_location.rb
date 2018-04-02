# Creates a dialog element with a yaml dump of information about a valid template for each
# selected destination location for the selected OS version.
#
# Parameters
#   dialog_os_tag
#   dialog_location_tags
#
@DEBUG = false

OS_TAG_DIALOG_OPTION         = 'dialog_os_tag'
LOCATION_TAGS_DIALOG_OPTION  = 'dialog_location_tags'

PROVISIONING_LAN_TAG_CATEGORY = 'network_purpose'
PROVISIONING_LAN_TAG_NAME     = 'provisioning'

require 'yaml'

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
  
  # get parameters
  os_tag         = $evm.root[OS_TAG_DIALOG_OPTION]
  location_tags  = $evm.root[LOCATION_TAGS_DIALOG_OPTION] || []
  $evm.log(:info, "os_tag        => #{os_tag}")        if @DEBUG
  $evm.log(:info, "location_tags => #{location_tags}") if @DEBUG
  
  invalid_selection = false
  value = []
  
  # invalid if expected provision lan tag category does not exist
  if !$evm.execute('category_exists?', PROVISIONING_LAN_TAG_CATEGORY)
    invalid_selection = true
    value << "Expected provisioning LAN Tag Category <#{PROVISIONING_LAN_TAG_CATEGORY}> does not exist."
  end
    
  # invalid if expected provision lan tag does not exist
  if !$evm.execute('tag_exists?', PROVISIONING_LAN_TAG_CATEGORY, PROVISIONING_LAN_TAG_NAME)
    invalid_selection = true
    value << "Expected provisioning LAN Tag <#{PROVISIONING_LAN_TAG_NAME}> in Tag Category <#{PROVISIONING_LAN_TAG_CATEGORY}> does not exist."
  end
  
  # invalid if no os template tag(s) selected
  if os_tag.blank?
    invalid_selection = true
    value << "OS must be selected to determine valid destination providers."
  end
  
  # invalid if no location tags selected
  location_tags.delete("null")
  if location_tags.empty?
    invalid_selection = true
    value << "Destination location(s) must be selected to determine valid destination providers."
  end
  
  # find appropriatlly tagged providers
  providers_by_tag              = {}
  provisioning_lans_by_provider = {}
  location_tags.each do |provider_tag_name|
    provider_tag_path = "/managed/#{provider_tag_name}"
    $evm.log(:info, "provider_tag_path => #{provider_tag_path}") if @DEBUG
    tagged_providers = $evm.vmdb(:ext_management_system).find_tagged_with(:all => provider_tag_path, :ns => "*")
    
    if tagged_providers.empty?
      tag = $evm.vmdb(:classification).find_by_name(provider_tag_name)
      $evm.log(:info, "provider_tag_name => '#{provider_tag_name}', tag => #{tag}") if @DEBUG
      invalid_selection = true
      value << "Could not find Provider with Tag <#{tag.parent.description}: #{tag.description}>"
    else
      # only select providers that have hosts that all have at least one LAN that is tagged with the provisioning LAN tag
      # also determine the viable provisioning LANs
      host_messages = []
      tagged_providers.select! do |tagged_provider|
        select = true
        
        # ensure that each host has at at least one provisioning LAN
        all_host_provisoning_lans = []
        tagged_provider.hosts.each do |host|
          
          # find all the host provisioning LANs
          host_provisioning_lans = []
          host.lans.each do |lan|
            host_provisioning_lans << lan if lan.tagged_with?(PROVISIONING_LAN_TAG_CATEGORY, PROVISIONING_LAN_TAG_NAME)
          end
          
          # invalid tagged provider if there is a single host without a provisioning tagged LAN
          select = !host_provisioning_lans.empty?
          if !select
            tag = $evm.vmdb(:classification).find_by_name("#{PROVISIONING_LAN_TAG_CATEGORY}/#{PROVISIONING_LAN_TAG_NAME}")
            message = "Provider <#{tagged_provider.name}> invalid because Host <#{host.name}> does not have a LAN with " +
                      "Tag <#{tag ? tag.parent.description : PROVISIONING_LAN_TAG_CATEGORY}: #{tag ? tag.description : PROVISIONING_LAN_TAG_NAME}>"
            $evm.log(:warn, message)
            host_messages << message
          end
          
          all_host_provisoning_lans << host_provisioning_lans.collect { |lan| lan.name }
        end
        $evm.log(:info, "all_host_provisoning_lans => #{all_host_provisoning_lans}") if @DEBUG
        
        # ensure there is a provisioning LAN that is tagged on all of the hosts on the provider 
        # `inject(:&) does an `&` opertion on all elements of the array, thus doing an intersection
        intersection_of_host_provisioning_lans = all_host_provisoning_lans.inject(:&)
        $evm.log(:info, "intersection_of_host_provisioning_lans => #{intersection_of_host_provisioning_lans}") if @DEBUG
        
        # determine whether this provider should be selected if there is at least one provisioning LAN shared by all hosts on the provider
        select = !intersection_of_host_provisioning_lans.empty?
        
        # save the viable provisoning LANs
        provisioning_lans_by_provider[tagged_provider.name] = intersection_of_host_provisioning_lans
        
        # return whether to select this provider or not
        select
      end
      
      # determine if found any tagged providers with required provisioning LAN
      if tagged_providers.empty?
        invalid_selection = true
        provider_tag = $evm.vmdb(:classification).find_by_name(provider_tag_name)
        lan_tag      = $evm.vmdb(:classification).find_by_name("#{PROVISIONING_LAN_TAG_CATEGORY}/#{PROVISIONING_LAN_TAG_NAME}")
        value << "Could not find Provider with Tag <#{provider_tag.parent.description}: #{provider_tag.description}> and with a " +
                 "LAN with Tag <#{lan_tag ? lan_tag.parent.description : PROVISIONING_LAN_TAG_CATEGORY}: #{lan_tag ? lan_tag.description : PROVISIONING_LAN_TAG_NAME}>" +
                 "on all hosts on the tagged provider."
        value.concat(host_messages)
      end
      
      providers_by_tag[provider_tag_name] = tagged_providers
    end
  end
  $evm.log(:info, "providers_by_tag              => #{providers_by_tag}")              if @DEBUG
  $evm.log(:info, "provisioning_lans_by_provider => #{provisioning_lans_by_provider}") if @DEBUG
  
  if !invalid_selection
    # ensure there are templates tagged with the correct OS
    tagged_templates = $evm.vmdb(:VmOrTemplate).find_tagged_with(:all => "/managed/#{os_tag}", :ns => "*")
    tagged_templates.select! { |tagged_template| tagged_template.template }
    $evm.log(:info, "tagged_templates => #{tagged_templates}") if @DEBUG
    if tagged_templates.empty?
      template_tag = $evm.vmdb(:classification).find_by_name(os_tag)
      invalid_selection = true
      value << "Could not find any Templates with Tag <#{template_tag.parent.description}: #{template_tag.description}>"
    end
  
    # sort templates tagged with the correct OS by the correctly tagged provider they line up with
    templates_by_provider_tag = {}
    tagged_templates.each do |tagged_template|
      template_provider = tagged_template.ext_management_system
      providers_by_tag.each do |provider_tag_name, providers|
        if providers.collect {|provider| provider.id}.include?(template_provider.id)
          templates_by_provider_tag[provider_tag_name] ||= []
          templates_by_provider_tag[provider_tag_name] << tagged_template
        end
      end
    end
    $evm.log(:info, "templates_by_provider_tag => #{templates_by_provider_tag}") if @DEBUG
  
    # determine the selected templates
    selected_templates = []
    location_tags.each do |provider_tag_name|
      provider_tag = $evm.vmdb(:classification).find_by_name(provider_tag_name)
      template_tag = $evm.vmdb(:classification).find_by_name(os_tag)
      if templates_by_provider_tag[provider_tag_name].blank?
        invalid_selection = true
        value << "Could not find Template with Tag <#{template_tag.parent.description}: #{template_tag.description}> on a Provider with Tag <#{provider_tag.parent.description}: #{provider_tag.description}>"
      else
        # NOTE: just choose the first valid one and warn if there was more then one valid selection
        selected_templates << templates_by_provider_tag[provider_tag_name].first
        $evm.log(:warn, "More then one valid Template available with Tag <#{template_tag.parent.description}: #{template_tag.description}> " +
                        "on a Provider with Tag <#{provider_tag.parent.description}: #{provider_tag.description}>") if templates_by_provider_tag[provider_tag_name].length > 1
      end
    end
  end
  
  # if invalid selection prepend a note as such
  # else valid selection, list selected providers
  if invalid_selection
    value.map! { |v| "    * #{v}" }
    value.unshift('INVALID SELECTION')
    value = value.join("\n")
  else
    value = []
    selected_templates.each do |selected_template|
      # NOTE: just choose the first valid provisioning LAN and warn there was more then one valid selection
      provisioning_lans = provisioning_lans_by_provider[selected_template.ext_management_system.name]
      provisioning_lan  = provisioning_lans.first
      $evm.log(:warn, "More then one valid provisioning LAN available with Tag <#{}: #{}> " +
                      " on Provider with Tag <#{}: #{}>") if provisioning_lans.length > 1
      
      # add the provider options
      value << {
        :provider         => selected_template.ext_management_system.name,
        :name             => selected_template.name,
        :guid             => selected_template.guid,
        :provisioning_lan => provisioning_lan
      }
    end
    value = value.to_yaml
  end
  
  # create dialog element
  dialog_field = $evm.object
  dialog_field["data_type"]  = "string"
  dialog_field['read_only']  = true
  dialog_field['value']      = value
  $evm.log(:info, "value => #{value}") if @DEBUG
end
