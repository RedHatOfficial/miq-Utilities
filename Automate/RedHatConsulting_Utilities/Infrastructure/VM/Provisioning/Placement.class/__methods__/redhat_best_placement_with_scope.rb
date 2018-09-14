#
# Description: This method is used to find the incoming templates cluster as well as hosts and storage that have the tag category
# prov_scope = 'all' && prov_scope = <group-name>
# Modified for RHEVM
#

module RedHatConsulting_Utilities
  module Automate
    module Infrastructure
      module VM
        module Provisioning
          module Placement
            class RedHatBestPlacementWithScope
              include RedHatConsulting_Utilities::StdLib::Core

              #############################
              # Configurable options
              #
              # maxium VMs per datastore, "0" is magic for "don't care"
              #############################
              STORAGE_MAX_VMS = 0

              ############################
              # Ignore datastores over this % full
              #############################
              STORAGE_MAX_PCT_USED = 100

              #############################
              # Set host sort order here
              # options: :active_provisioning_memory, :active_provisioning_cpu, :random
              #############################
              HOST_SORT_ORDER = [:active_provisioning_memory, :random].freeze

              #############################
              # Set storage sort order here
              # options: :active_provisioning_vms, :free_space, :free_space_percentage, :random
              #############################
              STORAGE_SORT_ORDER = [:free_space, :active_provisioning_vms, :random].freeze

              def initialize(handle = $evm)
                @handle = handle
                @DEBUG = true
              end

              def main

                # Get variables
                prov = @handle.root["miq_provision"]
                vm = prov.vm_template
                error('VM not specified') if vm.nil?
                user = prov.miq_request.requester
                error('User not specified') if user.nil?
                ems = vm.ext_management_system
                error("EMS not found for VM:<#{vm.name}>") if ems.nil?
                cluster = vm.ems_cluster
                error("Cluster not found for VM:<#{vm.name}>") if cluster.nil?
                log(:info, "Selected Cluster: [#{cluster.nil? ? 'nil' : cluster.name}]")

                # Get Tags that are in scope
                # Default is to look for Hosts and Datastores tagged with prov_scope = All or match to Group
                # This behavior can be overridden by modifying the hash returned in get_placement_filters
                tags = get_param(:placement_filters)
                log(:info, "Additional placement filters: <#{tags}>") if @DEBUG


                log(:info, "VM=<#{vm.name}>, Space Required=<#{vm.provisioned_storage}>, group=<#{user.normalized_ldap_group}>")
                log(:info, 'Required tags: ')
                tags.each do |cat, tags|
                  log(:info, "\t#{cat}->[#{tags.join(',')}]")
                end

                #############################
                # STORAGE LIMITATIONS
                #############################
                storage_max_vms = @handle.object['storage_max_vms']
                storage_max_vms = storage_max_vms.strip.to_i if storage_max_vms.kind_of?(String) && !storage_max_vms.strip.empty?
                storage_max_vms = STORAGE_MAX_VMS unless storage_max_vms.kind_of?(Numeric)
                storage_max_pct_used = @handle.object['storage_max_pct_used']
                storage_max_pct_used = storage_max_pct_used.strip.to_i if storage_max_pct_used.kind_of?(String) && !storage_max_pct_used.strip.empty?
                storage_max_pct_used = STORAGE_MAX_PCT_USED unless storage_max_pct_used.kind_of?(Numeric)
                log(:info, "storage_max_vms:<#{storage_max_vms}> storage_max_pct_used:<#{storage_max_pct_used}>") if @DEBUG


                #############################
                # Sort hosts
                #############################
                active_prov_data = prov.check_quota(:active_provisions)
                sort_data = []

                # Only consider hosts confined to the cluster where the template resides
                cluster.hosts.each do |h|
                  sort_data << sd = [[], h.name, h]
                  host_id = h.attributes['id'].to_i
                  HOST_SORT_ORDER.each do |type|
                    sd[0] << case type
                               # Multiply values by (-1) to cause larger values to sort first
                             when :active_provisioning_memory
                               active_prov_data[:active][:memory_by_host_id][host_id]
                             when :active_provisioning_cpu
                               active_prov_data[:active][:cpu_by_host_id][host_id]
                             when :random
                               rand(1000)
                             else
                               0
                             end
                  end
                end

                sort_data.sort! { |a, b| a[0] <=> b[0] }
                hosts = sort_data.collect(&:pop)
                log(:info, "Sorted host Order:<#{HOST_SORT_ORDER.inspect}> Results:<#{sort_data.inspect}>")

                host = storage = nil
                hosts.each do |h|
                  if h.maintenance
                    log(:info, "Skipping host: <#{h.name}> because is in maintenance") if @DEBUG
                    next
                  end
                  if h.power_state != 'on'
                    log(:info, "Skipping host: <#{h.name}> because powered off") if @DEBUG
                    next
                  end

                  #############################
                  # Only consider hosts that have the required tags
                  #############################
                  next unless infra_obj_is_eligible?(h, tags)

                  log(:info, "Host: <#{h.name}> acceptable as is sufficiently tagged") if @DEBUG

                  nvms = h.vms.length

                  #############################
                  # Only consider storages that have the tag category group=all
                  #############################
                  storages = h.writable_storages.select do |s|
                    infra_obj_is_eligible?(s, tags)
                  end

                  log(:info, "Evaluating storages:<#{storages.collect { |s| s.name }.join(", ")}>") if @DEBUG

                  #############################
                  # Filter out storages that do not have enough free space for the VM
                  #############################
                  active_prov_data = prov.check_quota(:active_provisions)
                  storages = storages.select do |s|
                    storage_id = s.attributes['id'].to_i
                    actively_provisioned_space = active_prov_data[:active][:storage_by_id][storage_id]
                    if s.free_space > vm.provisioned_storage + actively_provisioned_space
                      true
                    else
                      if @DEBUG
                        log(:info, "Skipping Datastore:<#{s.name}>, not enough free space for VM:<#{vm.name}>. "\
                          "Available:<#{s.free_space}>, Needs:<#{vm.provisioned_storage}>")
                      end
                      false
                    end
                  end

                  #############################
                  # Filter out storages number of VMs is greater than the max number of VMs allowed per Datastore
                  #############################
                  storages = storages.select do |s|
                    storage_id = s.attributes['id'].to_i
                    active_num_vms_for_storage = active_prov_data[:active][:vms_by_storage_id][storage_id].length
                    if (storage_max_vms == 0) || ((s.vms.size + active_num_vms_for_storage) < storage_max_vms)
                      true
                    else
                      if @DEBUG
                        log(:info, "Skipping Datastore:<#{s.name}>, max number of VMs:"\
                          "<#{s.vms.size + active_num_vms_for_storage}> exceeded")
                      end
                      false
                    end
                  end

                  #############################
                  # Filter out storages where percent used will be greater than the max % allowed per Datastore
                  #############################
                  storages = storages.select do |s|
                    storage_id = s.attributes['id'].to_i
                    active_pct_of_storage = ((active_prov_data[:active][:storage_by_id][storage_id]) / s.total_space.to_f) * 100
                    request_pct_of_storage = (vm.provisioned_storage / s.total_space.to_f) * 100

                    if (storage_max_pct_used == 100) ||
                      ((s.v_used_space_percent_of_total + active_pct_of_storage + request_pct_of_storage) < storage_max_pct_used)
                      true
                    else
                      if @DEBUG
                        log(:info, "Skipping Datastore:<#{s.name}> percent of used space "\
                          "#{s.v_used_space_percent_of_total + active_pct_of_storage + request_pct_of_storage} exceeded")
                      end
                      false
                    end
                  end

                  #############################
                  # Sort storage to determine target datastore
                  #############################
                  sort_data = []
                  storages.each_with_index do |s, idx|
                    sort_data << sd = [[], s.name, idx]
                    storage_id = s.attributes['id'].to_i
                    STORAGE_SORT_ORDER.each do |type|
                      sd[0] << case type
                               when :free_space
                                 # Multiply values by (-1) to cause larger values to sort first
                                 (s.free_space - active_prov_data[:active][:storage_by_id][storage_id]) * -1
                               when :free_space_percentage
                                 active_pct_of_storage = ((active_prov_data[:active][:storage_by_id][storage_id]) / s.total_space.to_f) * 100
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
                  log(:info, "Sorted storage Order:<#{STORAGE_SORT_ORDER.inspect}>  Results:<#{sort_data.inspect}>") if @DEBUG
                  selected_storage = sort_data.first
                  unless selected_storage.nil?
                    selected_idx = selected_storage.last
                    storage = storages[selected_idx]
                    host = h
                  end

                  # Stop checking if we have found both host and storage
                  if host && storage
                    log(:info, "Found tolerable host/storage combo: <#{host.name}>/<#{storage.name}>")
                    break
                  end

                end # END - hosts.each

                # Set Host
                obj = @handle.object
                log(:info, "Selected Host: <#{host.nil? ? "nil" : host.name}>")
                if host
                  obj["host"] = host
                  prov.set_host(host)
                end

                # Set Storage
                log(:info, "Selected Datastore: <#{storage.nil? ? "nil" : storage.name}>")
                if storage
                  obj["storage"] = storage
                  prov.set_storage(storage)
                end

                # Set cluster
                log(:info, "Selected Cluster: <#{cluster.nil? ? "nil" : cluster.name}>")
                if cluster
                  obj["cluster"] = cluster
                  prov.set_cluster(cluster)
                end

                log(:info, "vm: <#{vm.name}> host: <#{host.try(:name)}> storage: <#{storage.try(:name)}> "\
                  "cluster: <#{cluster.try(:name)}>")

                if (cluster.nil? && host.nil?) || storage.nil?
                  error('Either {host,cluster} or storage is nil - issue abort.')
                end
              end

              def infra_obj_is_eligible?(obj, tags)
                log(:info, "Checking infra object: <#{obj.name}> has correct tags") if @DEBUG
                ok = tags.all? do |key, value|
                  if value.is_a?(Array)
                    value.any? { |v| obj.tagged_with?(key, v) }
                  else
                    obj.tagged_with?(key, value)
                  end
                end
                log(:info, "\t...#{ok}") if @DEBUG
                return ok
              end

            end
          end
        end
      end
    end
  end
end
if __FILE__ == $PROGRAM_NAME
  RedHatConsulting_Utilities::Automate::Infrastructure::VM::Provisioning::Placement::RedHatBestPlacementWithScope.new.main()
end
