#
# Infrastructure Best Fit with Filters
#
# Should work with both VMWare (DRS clusters and not), and RHV.

# Working backwards, we need to select a datastore, and a cluster, and/or host.
# For RHV, we always set a cluster.
# For VMWare, it is setting a cluster, if there is a suitable DRS enabled cluster. Otherwise a host.
#
#
# Cluster selection:
# For RHV, we must set a cluster. VMWare is optional, used if any DRS clusters are suitably tagged.
#
# VMware placement logic which chooses placement based on:
#   Option 1. DRS cluster tagged with `Provisioning Scope - All` or `Provisioning Scope - USER GROUP`
#        A. If multiple DRS clusters are tagged one is picked at random
#        B. Storage is filtered by inspecting a random host and the storage must have Multi Host Access
#        C. Storage is then picked by using logic from `vmware_best_fit_least_utilized`
#   Option 2. If no DRS clusters appropriatlly tagged then check for Hosts tagged with `Provisioning Scope - All`
#     or `Provisioning Scope - USER GROUP`
#        A. If multiple Hosts are tagged pick one using logic from `vmware_best_fit_least_utilized`
#        B. Storage must be attached to host
#        C. Storage must be tagged with `Provisioning Scope - All` or `Provisioning Scope - USER GROUP`
#        D. Storage is then picked using logic from `vmware_best_fit_least_utilized`

module RedHatConsulting_Utilities
  module Automate
    module Infrastructure
      module VM
        module Provisioning
          module Placement
            class InfraBestFitWithScope
              include RedHatConsulting_Utilities::StdLib::Core

              def initialize(handle = $evm)
                @handle = handle
                @DEBUG = true

                @settings = RedHatConsulting_Utilities::StdLib::Core::Settings.new()
                @region = @handle.root['miq_server'].region_number

                @STORAGE_MAX_VMS = @settings.get_setting(@region, :placement_storage_max_vms, 0)
                @STORAGE_MAX_PCT_USED = @settings.get_setting(@region, :placement_storage_max_pct_used, 100)

                @HOST_SORT_ORDER = @settings.get_setting(@region, :placement_host_sort_oprder, [:active_provioning_memory, :current_memory_headroom, :random])
                @STORAGE_SORT_ORDER = @settings.get_setting(@region, :placement_storage_sort_oprder, [:free_space, :active_provisioning_vms, :random])

                @user = get_user
                @rbac_array = get_current_group_rbac_array
              end

              def main

                # Get variables
                @prov = @handle.root['miq_provision']
                @vm = @prov.vm_template
                error('VM not specified') if @vm.nil?
                @ems = @vm.ext_management_system
                error("EMS not found for VM:<#{@vm.name}>") if @ems.nil?

                # Get Tags that are in scope
                # Default is to look for Hosts and Datastores tagged with prov_scope = All or match to Group
                # This behavior can be overridden by modifying the hash returned in get_placement_filters
                @tags = get_param(:placement_filters)
                log(:info, "Additional placement filters: <#{@tags}>") if @DEBUG

                log(:info, "VM=<#{@vm.name}>, Space Required=<#{@vm.provisioned_storage}>, placement filters=<#{@tags}>")

                @need_specific_host = false

                case @prov.vm_template.vendor.downcase
                when 'redhat'
                  cluster = get_rhv_cluster
                  potential_hosts = cluster.hosts
                when 'vmware'
                  drs_clusters, clusters = get_vmware_clusters
                  if drs_clusters.length.zero?
                    cluster = drs_clusters.sample
                    powered_on_hosts = cluster.hosts.select { |host| host.power_state == 'on' }
                    potential_hosts = [powered_on_hosts.sample]
                    log(:info, 'Randomly select a powered on host from DRS cluster to use to determine storage '\
                    " options. Cluster hosts (powered on): <#{powered_on_hosts.collect(&:name)}>")
                  else
                    @need_specific_host = true
                    cluster = clusters.sample
                    potential_hosts = cluster.hosts
                    log(:info, 'No DRS clusters, or no suitably tagged DRS clusters.')
                  end
                end

                #############################
                # STORAGE LIMITATIONS
                #############################

                storage_max_vms = @handle.object['storage_max_vms']
                storage_max_vms = storage_max_vms.strip.to_i if storage_max_vms.is_a?(String) && !storage_max_vms.strip.empty?
                storage_max_vms = @STORAGE_MAX_VMS unless storage_max_vms.is_a?(Numeric)

                storage_max_pct_used = @handle.object['storage_max_pct_used']
                storage_max_pct_used = storage_max_pct_used.strip.to_i if storage_max_pct_used.is_a?(String) &&
                  !storage_max_pct_used.strip.empty?
                storage_max_pct_used = @STORAGE_MAX_PCT_USED unless storage_max_pct_used.is_a?(Numeric)
                log(:info, "storage_max_vms:<#{storage_max_vms}> storage_max_pct_used:<#{storage_max_pct_used}>")


                hosts = sort_hosts(@need_specific_host, potential_hosts)
                log(:info, "Selected Cluster: <#{cluster.name}>") unless cluster.nil?
                log(:info, "Selected Hosts: <#{hosts.collect(&:name)}>")

                storage, host = find_suitable_storage(potential_hosts)

                obj = @handle.object

                # If selected by DRS cluster
                # else if selected by host
                if @need_specific_host
                  log(:info, "Selected Host: <#{host.nil? ? 'nil' : host.name}> Will set_host()")
                  obj['host'] = host
                  @prov.set_host(host)
                else
                  log(:info, "Selected Cluster: <#{cluster.nil? ? 'nil' : cluster.name}>. Will set_cluster()")
                  obj['ems_cluster'] = cluster
                  @prov.set_cluster(cluster)
                end

                log(:info, "Selected Datastore: <#{storage.nil? ? 'nil' : storage.name}> Will set_storage()")
                if storage
                  obj['storage'] = storage
                  @prov.set_storage(storage)
                end

                log(:info, "vm=<#{@vm.name}> cluster=<#{cluster}> host=<#{host}> storage=<#{storage}>")

                return unless (cluster.nil? && host.nil?) || storage.nil?
                error('No DRS cluster tagged with the expected tags nor fall back option of host tagged with '\
                      'the expected tags could be found. Or no stroage with sufficent space tagged attached to '\
                      'selected DRS cluster or host tagged with the expected tags could be found. Ensure there '\
                      'is at least one DRS cluster or a host tagged with the expected tags and attached storage '\
                      'with sufficent space tagged with the correct tags.' + " { tags => #{@tags} }")
              end

              def infra_obj_is_eligible?(obj, tags)
                log(:info, "Checking infra object: <#{obj.name}> has correct tags") if @DEBUG
                ok = tags.all? do |key, value|
                  Array.wrap(value).any? { |v| obj.tagged_with?(key, v) }
                end
                log(:info, "\t...#{ok}") if @DEBUG
                ok
              end

              private

              def get_rhv_cluster
                cluster = @vm.ems_cluster
                error("Cluster not found for VM:<#{vm.name}>") if cluster.nil?
                log(:info, "get_rhv_cluster - Selected Cluster: [#{cluster.nil? ? 'nil' : cluster.name}]")

                error("Selected cluster will fail, user does not have RBAC permissions for it: [#{@rbac_array}]") unless object_eligible?(cluster)
                cluster
              end

              def get_vmware_clusters
                drs_clusters = clusters = []
                @ems.ems_clusters.each do |c|
                  next unless infra_obj_is_eligible?(c, @tags)
                  clusters << c
                  next unless c.drs_enabled
                  drs_clusters << c
                end
                return drs_clusters, clusters
              end

              def sort_hosts(need_specific_host, potential_hosts)
                if need_specific_host
                  log(:info, 'Require selecting specific host')

                  sort_data = []
                  log(:info, "Sorted host Order:<#{@HOST_SORT_ORDER.inspect}> Results:<#{sort_data.inspect}>")
                  active_prov_data = @prov.check_quota(:active_provisions)
                  potential_hosts.each do |h|
                    #############################
                    # Only consider hosts that have the required tags
                    #############################
                    next unless infra_obj_is_eligible?(h, @tags)

                    #############################
                    # Sort hosts
                    #############################
                    sort_data << sd = [[], h.name, h]
                    host_id = h.attributes['id'].to_i
                    @HOST_SORT_ORDER.each do |type|
                      sd[0] << case type
                                 # Multiply values by (-1) to cause larger values to sort first
                               when :active_provioning_memory
                                 active_prov_data[:active][:memory_by_host_id][host_id]
                               when :active_provioning_cpu
                                 active_prov_data[:active][:cpu_by_host_id][host_id]
                               when :current_memory_headroom
                                 h.current_memory_headroom * -1
                               when :current_memory_usage
                                 h.current_memory_usage
                               when :current_cpu_usage
                                 h.current_cpu_usage
                               when :random
                                 rand(1000)
                               else
                                 0
                               end
                    end
                  end

                  sort_data.sort! { |a, b| a[0] <=> b[0] }
                  hosts = sort_data.collect(&:pop)
                  log(:info, 'Found 0 hosts. Did you tag any?') if hosts.length.zero?
                else
                  log(:info, 'Assigning to cluster')
                  hosts = potential_hosts
                  # noop. Assigned above
                end
                hosts
              end


              def find_suitable_storage(hosts)
                log(:info, '> find_suitable_storage') if @DEBUG
                host = storage = nil

                suitably_tagged_ds = {}
                suitably_sized_ds = {}

                hosts.each do |h|
                  log(:info, "\t evaluating host #{h.name}") if @DEBUG
                  next unless h.power_state == 'on'

                  nvms = h.vms.length

                  #############################
                  # Only consider storages that have the required tag categories
                  #############################
                  storages = h.storages.select do |s|
                    log(:info, "evaluating storage #{s.name} with tags #{s.tags.inspect} against tags: #{@tags.inspect}") if @DEBUG
                    infra_obj_is_eligible?(s, @tags)
                  end

                  log(:info, "Evaluating storages: <#{storages.collect(&:name).join(',')}>")
                  if storages.empty?
                    log(:info, "Found 0 suitably tagged datastores on host: [#{host}]. Skipping to next host")
                    next
                  end

                  #
                  # MOVE OUTSIDE.
                  #
                  # # if using a DRS cluster then ensure the selected storage has Multi Host Access enabled
                  # #
                  # # there is an exception if the cluster only has one host in which case having
                  # # Multi Host Access enabled does not matter
                  # if cluster && cluster.hosts.length > 1
                  #   # NOTE: for whatever reason the multiplehostaccess parameter uses 0/1 instead of true/false for it's value
                  #   storages = storages.select { |s| s.multiplehostaccess == 1 }
                  #
                  #   if storages.empty?
                  #     error("No storages with Multiple Host Access enabled on a sample host <#{h.name}> from the the selected "\
                  #         "DRS cluster <#{cluster.name}>.")
                  #   end
                  # end

                  active_prov_data = @prov.check_quota(:active_provisions)
                  storages = storages.select do |s|
                    enough_space_for_vm?(s, active_prov_data) &&
                      under_full_count?(s, active_prov_data) &&
                      under_full_threshold?(s, active_prov_data)
                  end


                  #############################
                  # Sort storage to determine target datastore
                  #############################
                  sort_data = []
                  log(:info, "Filtered Storage Options: <#{storages}>") if @DEBUG
                  storages.each_with_index do |s, idx|
                    sort_data << sd = [[], s.name, idx]
                    storage_id = s.attributes['id'].to_i
                    @STORAGE_SORT_ORDER.each do |type|
                      sd[0] << case type
                               when :free_space
                                 # Multiply values by (-1) to cause larger values to sort first
                                 (s.free_space - active_prov_data[:active][:storage_by_id][storage_id]) * -1
                               when :free_space_percentage
                                 active_pct_of_storage =
                                   ((active_prov_data[:active][:storage_by_id][storage_id]) / s.total_space.to_f) * 100
                                 s.v_used_space_percent_of_total + active_pct_of_storage
                               when :active_provioning_vms
                                 active_prov_data[:active][:vms_by_storage_id][storage_id].length
                               when :random
                                 rand(1000)
                               else
                                 0
                               end
                    end
                  end

                  sort_data.sort! { |a, b| a[0] <=> b[0] }
                  log(:info, "Sorted storage Order:<#{@STORAGE_SORT_ORDER.inspect}>  Results:<#{sort_data.inspect}>")
                  selected_storage = sort_data.first
                  log(:info, "Selected Storage: <#{selected_storage}>")
                  unless selected_storage.nil?
                    selected_idx = selected_storage.last
                    storage = storages[selected_idx]
                    host = h

                    log(:info, "Selected Storage Index: <#{selected_idx}>") if @DEBUG
                    log(:info, "Selected Storage: <#{storage}>")
                    log(:info, "Selected Host: <#{host}>")
                    break
                  end

                end
                error("Unable to find suitable storage") if storage.nil?
                return storage, host
              end

              #############################
              # Check if storage has enough free space for the VM
              #############################
              def enough_space_for_vm?(s, active_prov_data)
                storage_id = s.attributes['id'].to_i
                actively_provisioned_space = active_prov_data[:active][:storage_by_id][storage_id]
                if s.free_space > @vm.provisioned_storage + actively_provisioned_space
                  if @debug
                    log(:info, "Active Provision Data inspect: [#{active_prov_data.inspect}]")
                    log(:info, "Active provision space requirement: [#{actively_provisioned_space}]")
                    log(:info, "Valid Datastore: [#{s.name}], enough free space for VM -- Available: "\
                          "[#{s.free_space}], Needs: [#{@vm.provisioned_storage}]")
                  end
                  true
                else
                  log(:info, "Skipping Datastore:<#{s.name}>, not enough free space for VM:<#{@vm.name}>. "\
                          "Available:<#{s.free_space}>, Needs:<#{@vm.provisioned_storage}>")
                  false
                end
              end

              #############################
              # Check if storage is under the count if VMs
              #############################
              def under_full_count?(s, active_prov_data)
                storage_id = s.attributes['id'].to_i
                active_num_vms_for_storage = active_prov_data[:active][:vms_by_storage_id][storage_id].length
                if @STORAGE_MAX_VMS.zero? || ((s.vms.size + active_num_vms_for_storage) < @STORAGE_MAX_VMS)
                  true
                else
                  log(:info, "Skipping Datastore:<#{s.name}>, max number of VMs:"\
                        "<#{s.vms.size + active_num_vms_for_storage}> exceeded")
                  false
                end
              end

              #############################
              # Check if storage is now+after < max % allowed per Datastore
              #############################

              def under_full_threshold?(s, active_prov_data)
                storage_id = s.attributes['id'].to_i
                active_pct_of_storage = ((active_prov_data[:active][:storage_by_id][storage_id]) / s.total_space.to_f) * 100
                request_pct_of_storage = (@vm.provisioned_storage / s.total_space.to_f) * 100

                if (@STORAGE_MAX_PCT_USED == 100) ||
                  ((s.v_used_space_percent_of_total + active_pct_of_storage + request_pct_of_storage) < @STORAGE_MAX_PCT_USED)
                  true
                else
                  log(:info, "Skipping Datastore:<#{s.name}> percent of used space "\
                        "#{s.v_used_space_percent_of_total + active_pct_of_storage + request_pct_of_storage} exceeded")
                  false
                end
              end

            end
          end
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  RedHatConsulting_Utilities::Automate::Infrastructure::VM::Provisioning::Placement::InfraBestFitWithScope.new.main
end
