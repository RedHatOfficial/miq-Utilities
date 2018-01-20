# Adds disks to an existing VM.
#
# NOTE:
#   Each disk is added one at a time in a retry loop.
#   This is done because providers sometimes get overwelmed by
#   to many add disk operations in a row so they need time to process each one.
#
# TESTED WITH:
#   VMware
#   RHV
#
# PARAMETERS
#   dialog_disk_option_prefix - Prefix of disk dialog options.
#                               Default is 'disk'
#   default_bootable          - Default value for whether a disk should be bootable if no disk specific value is passed.
#                               Default is false.
#   miq_provision             - VM Provisining request contianing the VM to resize the disk of
#                               Either this or vm are required.
#   vm                        - VM to resize the disk of.
#                               Either this or miq_provision are required.
#
#   $evm.root['miq_provision'].option || $evm.root.attributes
#     #{dialog_disk_option_prefix}_#_size           - Size of the disk to add in gigabytes.
#                                                     Required.
#                                                     Maybe prefixed with 'dialog_'.
#     #{dialog_disk_option_prefix}_#_thin_provision - Thin provision, or thick provision disk.
#                                                     Optional.
#                                                     Default is true.
#                                                     Maybe prefixed with 'dialog_'.
#     #{dialog_disk_option_prefix}_#_dependent      - Whether new disk is dependent.
#                                                     Optional.
#                                                     Default is true.
#                                                     Maybe prefixed with 'dialog_'.
#     #{dialog_disk_option_prefix}_#_persistent     - Whether new disk is persistent.
#                                                     Optional.
#                                                     Default is true.
#                                                     Maybe prefixed with 'dialog_'.
#     #{dialog_disk_option_prefix}_#_bootable       - Whether new disk is bootable.
#                                                     Optional.
#                                                     Default is #{default_bootable}.
#                                                     Maybe prefixed with 'dialog_'.
#
#     EX:
#       {
#         'disk_1_size'                    => 10,
#         'disk_2_size'                    => 5,
#         'disk_2_thin_provisioned'        => false,
#         'dialog_disk_3_size'             => 20,
#         'dialog_disk_3_thin_provisioned' => true,
#         'dialog_disk_3_dependent         => false,
#         'dialog_disk_3_persistent        => false,
#         'dialog_disk_3_bootable          => false
#       }
#
@DEBUG = true

# Perform a method retry for the given reason
#
# @param seconds Number of seconds to wait before next retry
# @param reason  Reason for the retry
def automate_retry(seconds, reason)
  $evm.root['ae_result']         = 'retry'
  $evm.root['ae_retry_interval'] = "#{seconds.to_i}.seconds"
  $evm.root['ae_reason']         = reason

  $evm.log(:info, "Retrying #{@method} after #{seconds} seconds, because '#{reason}'") if @DEBUG
  exit MIQ_OK
end

# There are many ways to attempt to pass parameters in Automate.
# This function checks all of them in priorty order as well as checking for symbol or string.
#
# Order:
#   1. Inputs
#   2. Current
#   3. Object
#   4. Root
#   5. State
#
# @return Value for the given parameter or nil if none is found
def get_param(param)  
  # check if inputs has been set for given param
  param_value ||= $evm.inputs[param.to_sym]
  param_value ||= $evm.inputs[param.to_s]
  
  # else check if current has been set for given param
  param_value ||= $evm.current[param.to_sym]
  param_value ||= $evm.current[param.to_s]
 
  # else cehck if current has been set for given param
  param_value ||= $evm.object[param.to_sym]
  param_value ||= $evm.object[param.to_s]
  
  # else check if param on root has been set for given param
  param_value ||= $evm.root[param.to_sym]
  param_value ||= $evm.root[param.to_s]
  
  # check if state has been set for given param
  param_value ||= $evm.get_state_var(param.to_sym)
  param_value ||= $evm.get_state_var(param.to_s)

  $evm.log(:info, "{ '#{param}' => '#{param_value}' }") if @DEBUG
  return param_value
end

begin
  # get parameters
  $evm.log(:info, "$evm.root['vmdb_object_type'] => '#{$evm.root['vmdb_object_type']}'.") if @DEBUG
  case $evm.root['vmdb_object_type']
    when 'miq_provision'
      miq_provision = $evm.root['miq_provision']
      vm            = miq_provision.vm
      options       = miq_provision.options
    
      #merge the ws_values and attributes into one list to make it easier to search
      options       = options.merge(options[:ws_values]) if options[:ws_values]
    when 'vm'
      vm      = get_param(:vm)
      options = $evm.root.attributes
    else
      error("Can not handle vmdb_object_type: #{$evm.root['vmdb_object_type']}")
  end
  error("vm not found")      if vm.blank?
  error("options not found") if options.blank?
  $evm.log(:info, "options => #{options}") if @DEBUG
  
  # get dialog option prefix
  disk_option_prefix = get_param(:dialog_disk_option_prefix)
  $evm.log(:info, "disk_option_prefix => #{disk_option_prefix}") if @DEBUG
  
  # new disk queue name
  new_disk_queue_name = "#{disk_option_prefix}_new_disks_queue".to_sym
  $evm.log(:info, "new_disk_queue_name => #{new_disk_queue_name}") if @DEBUG
  
  # if saved sate load from that
  # else first iteration and need to create disk queue
  new_disks_queue = nil
  if $evm.state_var_exist?(new_disk_queue_name)
    $evm.log(:info, "Loading saved state") if @DEBUG
    
    new_disks_queue = $evm.get_state_var(new_disk_queue_name)
  else
    $evm.log(:info, "Create new disk queue") if @DEBUG
    
    # determine the datastore name
    if !vm.storage.nil?
      datastore_name = vm.storage.name # NOTE: VMware expects datastore_name - https://bugzilla.redhat.com/show_bug.cgi?id=1536525
      datastore      = vm.storage.name # NOTE: RHV expects datastore         - https://bugzilla.redhat.com/show_bug.cgi?id=1536525
    elsif !miq_provision.nil?
      datastore_name = miq_provision.options[:dest_storage][1] # NOTE: VMware expects datastore_name - https://bugzilla.redhat.com/show_bug.cgi?id=1536525
      datastore      = miq_provision.options[:dest_storage][1] # NOTE: RHV expects datastore         - https://bugzilla.redhat.com/show_bug.cgi?id=1536525
    end
    $evm.log(:info, "datastore_name => #{datastore_name}") if @DEBUG
    $evm.log(:info, "datastore      => #{datastore}")      if @DEBUG
    error("datastore_name must not be nil") if datastore_name.nil? || datastore_name.empty?
    error("datastore must not be nil")      if datastore.nil?
    
    # get default options
    default_size             = get_param(:default_size)
    default_thin_provisioned = get_param(:default_thin_provisioned)
    default_dependent        = get_param(:default_dependent)
    default_persistent       = get_param(:default_persistent)
    default_bootable         = get_param(:default_bootable)
    $evm.log(:info, "default_size             => #{default_size}")             if @DEBUG
    $evm.log(:info, "default_thin_provisioned => #{default_thin_provisioned}") if @DEBUG
    $evm.log(:info, "default_dependent        => #{default_dependent}")        if @DEBUG
    $evm.log(:info, "default_persistent       => #{default_persistent}")       if @DEBUG
    $evm.log(:info, "default_bootable         => #{default_bootable}")         if @DEBUG
  
    # create the new disks queue
    new_disks_queue = {}
    options.select { |option, value| option.to_s =~ /^(dialog_)?#{disk_option_prefix}_([0-9]+)_/ }.each do |disk_option, disk_value|
      # determine new disk attribute
      captures  = disk_option.to_s.match(/#{disk_option_prefix}_([0-9]+)_(.*)/)
      disk_num  = captures[1]
      disk_attr = captures[2]
    
      # ensure these attributes are converted to booleans
      if (disk_attr == 'thin_provisioned' ||
          disk_attr == 'dependent' ||
          disk_attr == 'persistent' ||
          disk_attr == 'bootable')
      
        # if value is a string, convert to a boolean
        if disk_value.kind_of? String
          $evm.log(:info, "Convert disk attribute '#{disk_attr}' value to boolean: #{disk_value}") if @DEBUG
          disk_value = (disk_value =~ /t|true|y|yes/im) == 0
        end
      end
    
      # initialize new disk in queue using defaults
      new_disks_queue[disk_num] ||= {
        :datastore        => datastore,      # NOTE: RHV expects datastore         - https://bugzilla.redhat.com/show_bug.cgi?id=1536525
        :datastore_name   => datastore_name, # NOTE: VMware expects datastore_name - https://bugzilla.redhat.com/show_bug.cgi?id=1536525
        :size             => default_size,
        :thin_provisioned => default_thin_provisioned,
        :dependent        => default_dependent,
        :persistent       => default_persistent,
        :bootable         => default_bootable
      }
      
      # set specific new disk attribute
      new_disks_queue[disk_num][disk_attr.to_sym] = disk_value
    end
    
    # remove disks of 0 size from queue
    new_disks_queue.delete_if { |new_disk_num, new_disk_options| new_disk_options[:size].nil? || new_disk_options[:size] == 0 }
  end
  
  # get next disk off of queue
  $evm.log(:info, "new_disks_queue => #{new_disks_queue}") if @DEBUG
  unless new_disks_queue.empty?
    new_disk_num, new_disk_options = new_disks_queue.shift
  
    # add the aditional disk
    $evm.log(:info, "Add new disk of size '#{new_disk_options[:size]}G' to VM #{vm.name} with new_disk_options: #{new_disk_options}")
    size_mb = new_disk_options[:size].to_i * 1024 # assume size is in gigabytes
    vm.add_disk(
      nil, # API want's this to be nil, why it asks for it is unknown....
      size_mb,
      new_disk_options
    )
  else
    $evm.log(:info, "No disks left on queue #{new_disk_queue_name}") if @DEBUG
  end
  
  # if the new disk queue is not empty then iterate again
  # else done adding new disks
  unless new_disks_queue.empty?
    retry_interval = get_param(:retry_interval)
    
    # set the state for the next loop
    $evm.set_state_var(new_disk_queue_name, new_disks_queue)
    $evm.log(:info, "Set state { new_disks_queue => #{new_disks_queue} }") if @DEBUG
    
    # set retry
    $evm.log(:info, "More new disks to be added, retry in #{retry_interval} seconds.")
    $evm.root['ae_result']         = 'retry'
    $evm.root['ae_retry_interval'] = "#{retry_interval}.seconds"
  else
    $evm.set_state_var(new_disk_queue_name, nil)
    $evm.root['ae_result'] = 'ok'
  end
end
