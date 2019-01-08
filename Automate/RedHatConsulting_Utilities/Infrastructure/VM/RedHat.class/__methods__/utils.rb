#
# Utility library for Red Hat Virtualization
#
# @source https://manageiq.gitbook.io/mastering-cloudforms-automation-addendum/embedded_methods/chapter-1
require 'ovirtsdk4'

module Automation
  module Infrastructure
    module VM
      module RedHat
        class Utils

          def initialize(ems, handle = $evm)
            @handle         = handle
            @ems            = ems_to_service_model(ems)
            @connection     = connection(@ems)
          end          

          def vnic_profile(profile_name, network_name, dc_name)
            vnic_profile = vnic_profiles_service.list.select { |profile| 
              (profile.name == profile_name) && 
              (profile.network.id == network_by_name(network_name, dc_name).id)
            }.first
            vnic_profile
          end
          
          def vnic_profile_id(profile_name)	
            vnic_profile = vnic_profiles_service.list.select { |profile| 	
              profile.name == profile_name 	
            }.first	
            vnic_profile.id	
          end

          def vnic_profiles(dc_name)
            profiles = []
            vnic_profiles_service.list.each do |vnic_profile|
              network = network_by_id(vnic_profile.network.id, dc_name)
              profiles << {:id => vnic_profile.id, :name => "#{vnic_profile.name} (#{network.name})"}
            end
            profiles
          end

          private

          def ems_to_service_model(ems)
            raise "Invalid EMS" if ems.nil?
            # ems could be a numeric id or the ems object itself
            unless ems.is_a?(DRb::DRbObject) && /Manager/.match(ems.type.demodulize)
              if /^\d{1,13}$/.match(ems.to_s)
                ems = @handle.vmdb(:ems, ems)
              end
            end
            ems
          end

          def network_by_name(name, dc_name)
            networks(dc_name).detect { |n| n.name == name }
          end

          def network_by_id(id, dc_name)
            networks(dc_name).detect { |n| n.id == id }
          end

          def networks(dc_name)
            @connection.follow_link(dc(dc_name).networks)
          end

          def dc(name)
            dcs_service.list(search: "name=#{name}").first
          end

          def vnic_profiles_service
            @connection.system_service.vnic_profiles_service
          end

          def dcs_service
            @connection.system_service.data_centers_service
          end

          def connection(ems)
            connection = OvirtSDK4::Connection.new(
              url: "https://#{ems.hostname}/ovirt-engine/api",
              username: ems.authentication_userid,
              password: ems.authentication_password,
              insecure: true)
            connection if connection.test(true)
          end
        end
      end
    end
  end
end
