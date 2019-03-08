#  settings.rb

#  Author: Jeff Warnica <jwarnica@redhat.com> 2018-08-16
#
# Provides a common location for settings for RedHatConsulting_Utilities,
# and some defaults for the children project like rhc-miq-quickstart
#
# Settings are Global, Default, and by RegionID, with regional settings falling through to Default
#-------------------------------------------------------------------------------
#   Copyright 2018 Jeff Warnica <jwarnica@redhat.com>
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#-------------------------------------------------------------------------------
module RedHatConsulting_Utilities
  module StdLib
    module Core
      class Settings
        SETTINGS = {
            global: {
                #orderd list of CF tag names to use to lookup vlan names, _ separated
                # This helps build the setting name for VLAN lookups. Format is as:
                #    network_<template vendor>_key1_key2_..._keyN
                # consider the following examples
                #
                # vmware templates:
                # network_lookup_keys: %w(location environment)
                #         ---> network_vmware_NYC_DEV OR network_vmware_PARIS_QA
                # network_lookup_keys: %w(servicelevel location environment)
                #         ---> network_vmware_GOLD_NYC_DEV OR network_vmware_BRONZE_PARIS_QA
                #
                network_lookup_keys: %w(environment),

                #list of groups whose members can order services on behalf of others
                groups_can_order_for: %w(EvmGroup-super_administrator),

                vm_auto_start_suppress: true,
            },
            default: {
                # network/vlan/dvs names for the providers
                # these must exist, but can (likely will) change later in the process
                network_vmware: 'VM Network',
                network_redhat: '<Template>',
                retirement: 30.days.to_i,
                retirement_warn: 14.days.to_i,
                retirement_max_extensions: 3,

                #############################
                # Options for VM placement logic (for vmware_drs_cluster_best_fit_with_scope)
                #
                # @TODO: figure out how to have placement_filters here (implies eval(!))
                # @TODO: Reconcile RHV placement logic & use same config
                #
                # storage_max_vms: 0 - ignore
                #                  int - skip datastores with >x VMs
                #
                # storage_max_pct_used: 100 (default)
                #                       0-100  - skip datastores with >x % used.
                #
                # storage_sort_order: ordered array of keys to sort for "best" host
                #  0 or more of: :active_provisioning_vms, :free_space, :free_space_percentage, :random
                #
                # host_sort_order: ordered array of keys to sort for "best" datastore
                #
                # 0 or more of: :active_provioning_memory, :active_provioning_cpu, :current_memory_usage,
                #          :current_memory_headroom, :current_cpu_usage, :random
                #############################

                storage_max_vms: 0,
                storage_max_pct_used: 100,
                host_sort_order: [:active_provioning_memory, :current_memory_headroom, :random],
                storage_sort_order: [:active_provisioning_vms, :random],

        },
            r901: {
                network_vmware: 'dvs_0810_INF_VMS_PRD_HFLEX',
                network_vmware_test: 'dvs_0820_Self_Prov_Test(10.43.181.x)',
                network_vmware_dev: 'dvs_0821_Self_Prov_Dev(10.43.182.x)',
                default_custom_spec: 'Win2016(all versions)-Dev-Test-len',
                default_custom_spec_prefix: 'Win2016(all versions)-Dev-Test',
                ipam_dhcp_range_dev: 'Self_Provo_Dev',
                ipam_dhcp_range_test: 'Self_Provo_Test',
                infoblox_url: 'https://10.111.105.203/wapi/v2.6.1/',
            },
        }

        ##
        # Gets setting from our configuration hash above
        #
        # == Parameters:
        # region:
        #   A string which is a region number, or the symbol :global
        # key:
        #   The key to fetch from the selected region, or default if the key is not found in the region
        # default:
        #   if set, the default value to return if a key is not found (suppresses all errors)
        def get_setting(region, key, default = nil)
          region = ('r' + region.to_s).to_sym unless region == :global
          key = key.to_sym
          begin
            raise(KeyError, "region [#{region}] does not exist in settings hash and no default provided") unless SETTINGS.key?(region)
            return SETTINGS[region][key] if SETTINGS[region].key?(key)
            raise(KeyError, "key [#{key}] does not exist in region [#{region}] or defaults settings hash, and no default provided") unless SETTINGS[:default].key?(key)
            return SETTINGS[:default][key]
          rescue KeyError => e
            if default.nil?
              raise e
            else
              return default
            end
          end
        end

      end
    end
  end
end

# settings = RedHatConsulting_Utilities::StdLib::Core::Settings.new()
# puts settings.get_setting(901, :network_vmware)
#
# x = settings.get_setting(901, :default_custom_spec) rescue "no x"
# puts x
#
# x = settings.get_setting(:global, :network_lookup_keys) rescue "no x"
# puts x
#
# @region = 901
# x = settings.get_setting(@region, 'infoblox_url')
# puts x
#
# x = settings.get_setting(@region, 'custom_obscure_setting', {a: 'b'})
# puts x
#
# begin
#   x = settings.get_setting(@region, 'custom_obscure_setting')
#   puts x
# rescue KeyError => e
#   puts "supposed to fail. All is OK: [#{e}]"
# end
