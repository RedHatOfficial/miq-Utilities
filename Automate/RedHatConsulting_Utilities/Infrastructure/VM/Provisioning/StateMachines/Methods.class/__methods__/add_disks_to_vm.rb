# Adds disks to an existing VM.
#
# PARAMETERS
#   $evm.root
#     miq_provision - VM Provisining request contianing the VM to resize the disk of
#                     Either this or vm are required.
#     vm            - VM to resize the disk of.
#                     Either this or miq_provision are required.
#
#   $evm.root['miq_provision'].option || $evm.root.attributes
#     disk_#_size             - Size of the disk to add in gigabytes.
#                               Required.
#                               Maybe prefixed with 'dialog_'.
#     disk_#disk_#_dependent - Thin provision, or thick provision disk.
#                               Optional.
#                               Default is true.
#                               Maybe prefixed with 'dialog_'.
#     disk_#_dependent        - Whether new disk is dependent.
#                               Optional.
#                               Default is true.
#                               Maybe prefixed with 'dialog_'.
#     disk_#_persistent       - Whether new disk is persistent.
#                               Optional.
#                               Default is true.
#                               Maybe prefixed with 'dialog_'.
#     disk_#_bootable         - Whether new disk is bootable.
#                               Optional.
#                               Default is false.
#                               Maybe prefixed with 'dialog_'.
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

begin
  # get parameters
  $evm.log(:info, "$evm.root['vmdb_object_type'] => '#{$evm.root['vmdb_object_type']}'.") if @DEBUG
  case $evm.root['vmdb_object_type']
    when 'miq_provision'
      miq_provision = $evm.root['miq_provision']
      vm            = miq_provision.vm
      options       = miq_provision.options
    when 'vm'
      vm      = get_param(:vm)
      options = $evm.root.attributes
    else
      error("Can not handle vmdb_object_type: #{$evm.root['vmdb_object_type']}")
  end
  error("vm not found")      if vm.blank?
  error("options not found") if options.blank?
  
  # ensure VM storage is detected so new VM disks can be added to same storage
  if vm.storage.nil?
    $evm.log(:info, "VM storage not detected yet, perform VM refresh and retry") if @DEBUG
    vm.refresh
    automate_retry(30, 'Wait for VM refresh to detect VM storage')  
  else
    $evm.log(:info, "vm.stroage => #{vm.storage.name}") if @DEBUG
    $evm.root['ae_result'] = 'ok'
  end
  
  # collect new disk info
  new_disks = {}
  options.select { |option, value| option.to_s =~ /^(dialog_)?disk_([0-9]+)_/ }.each do |disk_option, disk_value|
    # determine new disk attribute
    captures  = disk_option.to_s.match(/disk_([0-9]+)_(.*)/)
    disk_num  = captures[1]
    disk_attr = captures[2]
    
    # set new disk attribute
    new_disks[disk_num]          ||= {}
    new_disks[disk_num][disk_attr] = disk_value
  end
  
  # create disks
  $evm.log(:info, "new_disks => #{new_disks}") if @DEBUG
  new_disks.each do |disk_num, disk_options|
    $evm.log(:info, "{ disk_num => #{disk_num}, disk_options => #{disk_options} }") if @DEBUG
    
    size             = disk_options['size']             || 0
    thin_provisioned = disk_options['thin_provisioned'] || true
    dependent        = disk_options['dependent']        || true
    persistent       = disk_options['persistent']       || true
    bootable         = disk_options['bootable']         || false
    
    # don't add disks with a size of 0
    if disk_options['size'].nil? || disk_options['size'] == 0
      $evm.log(:info, "Skip disk '#{disk_num}' with size of 0")
      next
    end
    
    # add the aditional disk
    $evm.log(:info, "Add new disk of size '#{size}'G to VM '#{vm.name}'") if @DEBUG
    size_mb = size.to_i * 1024 # assume size is in gigabytes
    vm.add_disk(
      nil, # API want's this to be nil, why it asks for it is unknown....
      size_mb,
      {
        :thinProvisioned => thin_provisioned,
        :dependent       => dependent,
        :persistent      => persistent,
        :bootable        => bootable
      }
    )
  end
end
