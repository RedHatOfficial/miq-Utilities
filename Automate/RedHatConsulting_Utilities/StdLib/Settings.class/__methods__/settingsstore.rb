#  settingsstore.rb
#
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

      # Settings handles storage and access of, er, settings. These can be Global, or bound to a RegionID, or a default
      # in the cases where there are no specific region settings.
      class SettingsStorage < Settings

        PRIORITY = 0

        SETTINGS = {
          global: {

            # list of groups whose members can order services on behalf of others
            groups_can_order_for: %w(EvmGroup-super_administrator),

            vm_auto_start_suppress: true,
          },
          default: {


            #############################
            # Options for VM placement logic (for vmware_drs_cluster_best_fit_with_scope & redhat_best_placement_with_scope)
            #
            # @TODO: figure out how to have placement_filters here (implies eval(!))
            # @TODO: Reconcile RHV placement logic
            #
            # storage_max_vms: 0 - ignore
            #                  >0 - skip datastores with >x VMs
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
        }.freeze

      end
    end
  end
end

