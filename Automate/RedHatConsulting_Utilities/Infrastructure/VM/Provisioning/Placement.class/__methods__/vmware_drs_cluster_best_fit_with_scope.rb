# VMware placment logic which chooses placment based on:
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
            class VmWareDrsClusterBestFitWithScope
              include RedHatConsulting_Utilities::StdLib::Core

              STORAGE_MAX_VMS = 0
              STORAGE_MAX_PCT_USED = 100

              #############################
              # Set host sort order here
              # options: :active_provioning_memory, :active_provioning_cpu, :current_memory_usage,
              #          :current_memory_headroom, :current_cpu_usage, :random
              #############################
              HOST_SORT_ORDER = [:active_provioning_memory, :current_memory_headroom, :random].freeze

              #############################
              # Set storage sort order here
              # options: :active_provisioning_vms, :free_space, :free_space_percentage, :random
              #############################
              STORAGE_SORT_ORDER = [:active_provisioning_vms, :random].freeze

              def initialize(handle = $evm)
                @handle = handle
                @DEBUG = true
              end

              def main
                # Get variables
                prov = @handle.root['miq_provision']
                vm = prov.vm_template
                error('VM not specified') if vm.nil?
                ems = vm.ext_management_system
                error("EMS not found for VM:<#{vm.name}>") if ems.nil?

                # Get Tags that are in scope
                # Default is to look for Hosts and Datastores tagged with prov_scope = All or match to Group
                # This behavior can be overridden by modifying the hash returned in get_placement_filters
                tags = get_param(:placement_filters)
                log(:info, "Additional placement filters: <#{tags}>") if @DEBUG

                log(:info, "VM=<#{vm.name}>, Space Required=<#{vm.provisioned_storage}>, " \
                  "placement filters=<#{tags}>")

                #############################
                # STORAGE LIMITATIONS
                #############################

                storage_max_vms = @handle.object['storage_max_vms']
                storage_max_vms = storage_max_vms.strip.to_i if storage_max_vms.is_a?(String) && !storage_max_vms.strip.empty?
                storage_max_vms = STORAGE_MAX_VMS unless storage_max_vms.is_a?(Numeric)

                storage_max_pct_used = @handle.object['storage_max_pct_used']
                storage_max_pct_used = storage_max_pct_used.strip.to_i if storage_max_pct_used.is_a?(String) &&
                                                                          !storage_max_pct_used.strip.empty?
                storage_max_pct_used = STORAGE_MAX_PCT_USED unless storage_max_pct_used.is_a?(Numeric)
                log(:info, "storage_max_vms:<#{storage_max_vms}> storage_max_pct_used:<#{storage_max_pct_used}>")

                #############################
                # Find a DRS-enabled cluster
                #############################
                drs_clusters = []
                ems.ems_clusters.each do |c|
                  next unless c.drs_enabled
                  #############################
                  # Only consider DRS clusters that have the required tags
                  #############################
                  next unless tags.all? do |key, value|
                    if value.is_a?(Array)
                      value.any? { |v| c.tagged_with?(key, v) }
                    else
                      c.tagged_with?(key, value)
                    end
                  end
                  drs_clusters << c
                end

                # If no tagged DRS clusters search hosts
                # else tagged DRS clusters, pick one at random
                if drs_clusters.length.zero?
                  log(:info, 'No correctly tagged DRS clusters. Select non-DRS cluster')

                  #############################
                  # No DRS cluster found - try hosts
                  #############################

                  sort_data = []
                  log(:info, "Sorted host Order:<#{HOST_SORT_ORDER.inspect}> Results:<#{sort_data.inspect}>")
                  active_prov_data = prov.check_quota(:active_provisions)
                  ems.hosts.each do |h|
                    #############################
                    # Only consider hosts that have the required tags
                    #############################
                    next unless tags.all? do |key, value|
                      if value.is_a?(Array)
                        value.any? { |v| h.tagged_with?(key, v) }
                      else
                        h.tagged_with?(key, value)
                      end
                    end

                    #############################
                    # Sort hosts
                    #############################
                    sort_data << sd = [[], h.name, h]
                    host_id = h.attributes['id'].to_i
                    HOST_SORT_ORDER.each do |type|
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
                  log(:info, 'Select DRS cluster')

                  #############################
                  # Tagged DRS cluster found - pick one at random
                  #############################
                  cluster = drs_clusters.sample

                  # Pick a random host on the tagged DRS cluster to then search for
                  # associated storage tagged with Multi Host Access
                  #
                  # NOTE: in the case of using a tagged DRS cluster host tags are ignored since VMware will choose the host
                  powered_on_hosts = cluster.hosts.select { |host| host.power_state == 'on' }
                  log(:info, 'Randomly select a powered on host from DRS cluster to use to determine storage '\
                    " options. Cluster hosts (powered on): <#{powered_on_hosts.collect(&:name)}>")
                  hosts = [powered_on_hosts.sample]
                end
                log(:info, "Selected Cluster: <#{cluster.name}>") unless cluster.nil?
                log(:info, "Selected Hosts: <#{hosts.collect(&:name)}>")

                host = storage = nil
                min_registered_vms = nil
                hosts.each do |h|
                  next unless h.power_state == 'on'
                  log(:info, "evaluating host #{h.name}") if @DEBUG

                  nvms = h.vms.length

                  #############################
                  # Only consider storages that have the required tag categories
                  #############################
                  storages = h.storages.select do |s|
                    log(:info, "evaluating storage #{s.name} with tags #{s.tags.inspect} against tags: #{tags.inspect}") if @DEBUG
                    tags.all? do |key, value|
                      if value.is_a?(Array)
                        value.any? { |v| s.tagged_with?(key, v) }
                      else
                        s.tagged_with?(key, value)
                      end
                    end
                  end

                  log(:info, "Evaluating storages:<#{storages.collect(&:name).join(',')}>")

                  # if using a DRS cluster then ensure the selected storage has Multi Host Access enabled
                  #
                  # there is an exception if the cluster only has one host in which case having
                  # Multi Host Access enabled does not matter
                  if cluster && cluster.hosts.length > 1
                    # NOTE: for whatever reason the multiplehostaccess parameter uses 0/1 instead of true/false for it's value
                    storages = storages.select { |s| s.multiplehostaccess == 1 }

                    if storages.empty?
                      error("No storages with Multiple Host Access enabled on a sample host <#{h.name}> from the the selected "\
                          "DRS cluster <#{cluster.name}>.")
                    end
                  end

                  #############################
                  # Filter out storages that do not have enough free space for the VM
                  #############################
                  active_prov_data = prov.check_quota(:active_provisions)
                  storages = storages.select do |s|
                    storage_id = s.attributes['id'].to_i
                    actively_provisioned_space = active_prov_data[:active][:storage_by_id][storage_id]
                    if s.free_space > vm.provisioned_storage + actively_provisioned_space
                      if @debug
                        log(:info, "Active Provision Data inspect: [#{active_prov_data.inspect}]")
                        log(:info, "Active provision space requirement: [#{actively_provisioned_space}]")
                        log(:info, "Valid Datastore: [#{s.name}], enough free space for VM -- Available: "\
                          "[#{s.free_space}], Needs: [#{vm.provisioned_storage}]")
                      end

                      true
                    else
                      log(:info, "Skipping Datastore:<#{s.name}>, not enough free space for VM:<#{vm.name}>. "\
                          "Available:<#{s.free_space}>, Needs:<#{vm.provisioned_storage}>")
                      false
                    end
                  end

                  #############################
                  # Filter out storages number of VMs is greater than the max number of VMs allowed per Datastore
                  #############################
                  storages = storages.select do |s|
                    storage_id = s.attributes['id'].to_i
                    active_num_vms_for_storage = active_prov_data[:active][:vms_by_storage_id][storage_id].length
                    if storage_max_vms.zero? || ((s.vms.size + active_num_vms_for_storage) < storage_max_vms)
                      true
                    else
                      log(:info, "Skipping Datastore:<#{s.name}>, max number of VMs:"\
                        "<#{s.vms.size + active_num_vms_for_storage}> exceeded")
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
                      log(:info, "Skipping Datastore:<#{s.name}> percent of used space "\
                        "#{s.v_used_space_percent_of_total + active_pct_of_storage + request_pct_of_storage} exceeded")
                      false
                    end
                  end

                  next unless min_registered_vms.nil? || nvms < min_registered_vms
                  #############################
                  # Sort storage to determine target datastore
                  #############################
                  sort_data = []
                  log(:info, "Filtered Storage Options: <#{storages}>") if @DEBUG
                  storages.each_with_index do |s, idx|
                    sort_data << sd = [[], s.name, idx]
                    storage_id = s.attributes['id'].to_i
                    STORAGE_SORT_ORDER.each do |type|
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
                  log(:info, "Sorted storage Order:<#{STORAGE_SORT_ORDER.inspect}>  Results:<#{sort_data.inspect}>")
                  selected_storage = sort_data.first
                  log(:info, "Selected Storage: <#{selected_storage}>")
                  unless selected_storage.nil?
                    selected_idx = selected_storage.last
                    storage = storages[selected_idx]
                    host = h

                    log(:info, "Selected Storage Index: <#{selected_idx}>") if @DEBUG
                    log(:info, "Selected Storage: <#{storage}>")
                    log(:info, "Selected Host: <#{host}>")
                  end

                  # Stop checking if we have found both host and storage
                  break if host && storage
                end

                obj = @handle.object

                # If selected by DRS cluster
                # else if selected by host
                if cluster
                  log(:info, "Selected Cluster: <#{cluster.nil? ? 'nil' : cluster.name}>. Will set_cluster()")
                  obj['ems_cluster'] = cluster
                  prov.set_cluster(cluster)
                elsif host
                  log(:info, "Selected Host: <#{host.nil? ? 'nil' : host.name}> Will set_host()")
                  obj['host'] = host
                  prov.set_host(host)
                end

                log(:info, "Selected Datastore: <#{storage.nil? ? 'nil' : storage.name}> Will set_storage()")
                if storage
                  obj['storage'] = storage
                  prov.set_storage(storage)
                end

                log(:info, "vm=<#{vm.name}> cluster=<#{cluster}> host=<#{host}> storage=<#{storage}>")

                return unless (cluster.nil? && host.nil?) || storage.nil?
                error('No DRS cluster tagged with the expected tags nor fall back option of host tagged with '\
                      'the expected tags could be found. Or no stroage with sufficent space tagged attached to '\
                      'selected DRS cluster or host tagged with the expected tags could be found. Ensure there '\
                      'is at least one DRS cluster or a host tagged with the expected tags and attached storage '\
                      'with sufficent space tagged with the correct tags.' + " { tags => #{tags} }")
              end
            end
          end
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  RedHatConsulting_Utilities::Automate::Infrastructure::VM::Provisioning::Placement::VmWareDrsClusterBestFitWithScope.new.main
end
