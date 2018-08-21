# Tags a given set of LANs associated with currently selected VMDB object with a given set of tags
#
# Parameters
#   @handle.root['dialog_multiselect_tags']
#   @handle.root['dialog_single_value_tag']
#
#
@DEBUG = false

module RedHatConsulting_Utilities
  module Automate
    module System
      module CommonMethods
        module TaggingMethods
          class AddTagToLans
            include RedHatConsulting_Utilities::StdLib::Core

            def initialize(handle = @handle)
              @handle = handle
              @DEBUG = false
            end

            def main

              dump_root() if @DEBUG
              dump_current() if @DEBUG

              # get the host(s) that the LANs are associated with that need to be tagged
              vmdb_object_type = @handle.root['vmdb_object_type']
              case vmdb_object_type
              when 'ext_management_system'
                ems = @handle.root['ext_management_system']
                @handle.log(:info, "ems=#{ems.name}") if @DEBUG

                hosts = ems.hosts
              when 'ems_cluster'
                cluster = @handle.root['ems_cluster']
                @handle.log(:info, "cluster=#{cluster.name}") if @DEBUG

                hosts = cluster.hosts
              when 'host'
                host = @handle.root['host']
                @handle.log(:info, "host=#{host.name}") if @DEBUG

                hosts = [host]
              else
                error("@handle.root['vmdb_object_type']=#{@handle.root['vmdb_object_type']} is not one of expected ['ext_management_system', 'ems_cluster', 'host'].")
              end

              # get the parameters
              multi_select_tag_names = @handle.root['dialog_multiselect_tags'] # could have selected multiple
              single_value_tag_name = @handle.root['dialog_single_value_tag'] # could have selected one
              lan_names = @handle.root['dialog_lan_names']
              @handle.log(:info, "multi_select_tag_names => #{multi_select_tag_names}") if @DEBUG
              @handle.log(:info, "single_value_tag_name  => #{single_value_tag_name}") if @DEBUG
              @handle.log(:info, "lan_names    => #{lan_names}") if @DEBUG

              # find the lans by name or id
              selected_lans_to_hosts = {}
              hosts.each do |host|
                host.lans.each do |lan|
                  selected_lans_to_hosts[lan] = host if lan_names.include?(lan.name) || lan_names.include?(lan.id)
                end
              end
              @handle.log(:info, "selected_lans_to_hosts => #{selected_lans_to_hosts}") if @DEBUG

              # create the new_tags list
              # NOTE: this is a bit of a cheat in that really only single_value_tag_name or multi_select_tag_names should have values
              #       and this could be verified against the selected tag category. But being lazy and just makeing assumptions that
              #       is all already handled before we get here.
              new_tags = []
              new_tags << single_value_tag_name if !single_value_tag_name.blank?
              multi_select_tag_names.each { |tag_name| new_tags << tag_name }
              @handle.log(:info, "new_tags => #{new_tags}") if @DEBUG

              # tag all the VLANs
              selected_lans_to_hosts.each do |lan, host|
                new_tags.each do |new_tag|
                  @handle.log(:info, "Assign Tag <#{new_tag}> to LAN <#{lan.name}> on Host <#{host.name}> on Provider <#{host.ext_management_system.name}>") if @DEBUG
                  tag_category, tag_name = new_tag.split('/')
                  already_assigned = lan.tagged_with?(tag_category, tag_name)
                  @handle.log(:info, "tag_category     => #{tag_category}") if @DEBUG
                  @handle.log(:info, "tag_name         => #{tag_name}") if @DEBUG
                  @handle.log(:info, "already_assigned => #{already_assigned}") if @DEBUG

                  # only attempt to tag if not already tagged
                  tag = @handle.vmdb(:classification).find_by_name(new_tag)
                  if !already_assigned
                    # attempt to tag the LAN
                    lan.tag_assign(new_tag)

                    # verify the LAN is now tagged
                    now_assigned = lan.tagged_with?(tag_category, tag_name)
                    @handle.log(:info, "now_assigned => #{now_assigned}") if @DEBUG

                    # send message
                    if now_assigned
                      message = "Tag <#{tag.parent.description}: #{tag.description}> has been assigned to " +
                        "LAN <#{lan.name} (#{lan.switch.name})> " +
                        "on Host <#{host.name}> " +
                        "on Provider <#{host.ext_management_system.name}>"
                      @handle.create_notification(:level => 'info', :message => message)
                      @handle.log(:info, message)
                    else
                      message = "Tag <#{tag.parent.description}: #{tag.description}> failed to be assigned to " +
                        "LAN <#{lan.name} (#{lan.switch.name})> " +
                        "on Host <#{host.name}> " +
                        "on Provider <#{host.ext_management_system.name}>"
                      @handle.create_notification(:level => 'error', :message => message)
                      @handle.log(:error, message)
                    end
                  else
                    message = "Tag <#{tag.parent.description}: #{tag.description}> already assigned to " +
                      "LAN <#{lan.name} (#{lan.switch.name})> " +
                      "on Host <#{host.name}> " +
                      "on Provider <#{host.ext_management_system.name}>"
                    @handle.log(:info, message)
                  end
                end
              end
            rescue => error
              message = "Unexpected error tagging LANs. See log for more details. #{error}"
              @handle.create_notification(:level => 'error', :message => message)
              error(message + "\n#{error.backtrace.join("\n")}")
            end

          end #main

        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  RedHatConsulting_Utilities::Automate::System::CommonMethods::TaggingMethods::AddTagToLans.new.main
end
