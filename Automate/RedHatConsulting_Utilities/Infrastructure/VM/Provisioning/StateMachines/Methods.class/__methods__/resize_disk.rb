# Adds the given VM to service specified on the provision request.
#
# PARAMETERS
#   EVM ROOT
#     miq_provision - VM Provisining request contianing the VM to resize the disk of
#                     Either this or vm are required.
#     vm            - VM to resize the disk of.
#                     Either this or miq_provision are required.
#     disk_number   - Number of the disk to resize.
#                     Optional.
#                     Defaults to 1.
#     disk_size     - The size to make the disk
#                     Required.
#
# SEE
#   http://talk.manageiq.org/t/how-can-i-resize-a-vmware-disk/381/4
@DEBUG = true

# Log an error and exit.
#
# @param msg Message to error with
def error(msg)
  $evm.log(:error, msg)
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = msg.to_s
  exit MIQ_STOP
end

# Dumps all of the root attributes to the log
def dump_root()
  $evm.log(:info, "Root:<$evm.root> Begin $evm.root.attributes")
  $evm.root.attributes.sort.each { |k, v| $evm.log(:info, "Root:<$evm.root> Attribute - #{k}: #{v}")}
  $evm.log(:info, "Root:<$evm.root> End $evm.root.attributes")
  $evm.log(:info, "")
end

# TODO: DOC ME
def automate_retry(seconds, reason)
  $evm.root['ae_result'] = 'retry'
  $evm.root['ae_retry_interval'] = "#{seconds.to_i}.seconds"
  $evm.root['ae_reason'] = reason

  $evm.log(:info, "Retrying #{@method} after #{seconds} seconds, because '#{reason}'")
  exit MIQ_OK
end

# @source http://talk.manageiq.org/t/how-can-i-resize-a-vmware-disk/381/4
def resizeDisk(vm, disk_number, new_disk_size_in_kb)
  vm_base = vm.object_send('instance_eval', 'self')
  ems = vm.ext_management_system

  ems.object_send('instance_eval', '
  def resize_disk(vm, diskIndex, new_disk_size_in_kb)
    #self.get_vim_vm_by_mor(vm.ems_ref) do | vimVm |
    vm.with_provider_object do | vimVm |
      devices = vimVm.send(:getProp, "config.hardware")["config"]["hardware"]["device"]

      matchedDev = nil
      currentDiskIndex = 0
      devices.each do | dev |
        next if dev.xsiType != "VirtualDisk"
        if diskIndex == currentDiskIndex
          matchedDev = dev
          break
        end
        currentDiskIndex += 1
      end
      raise "resize_disk: disk #{diskIndex} not found" unless matchedDev
      $log.info("resize_disk: resizing using matched device at #{diskIndex}")

      vmConfigSpec = VimHash.new("VirtualMachineConfigSpec") do |vmcs|
        vmcs.deviceChange = VimArray.new("ArrayOfVirtualDeviceConfigSpec") do |vmcs_vca|
          vmcs_vca << VimHash.new("VirtualDeviceConfigSpec") do |vdcs|
            vdcs.operation = "edit".freeze
            vdcs.device    = VimHash.new("VirtualDisk") do |vDev|
              vDev.key           = matchedDev["key"]
              vDev.controllerKey = matchedDev["controllerKey"]
              vDev.unitNumber    = matchedDev["unitNumber"]
              vDev.backing       = matchedDev["backing"]
              vDev.capacityInKB  = new_disk_size_in_kb
            end
          end
        end
      end
      $log.info("resize_disk: attempting to reconfigure vm with spec: \'#{vmConfigSpec}\'")
      vimVm.send(:reconfig, vmConfigSpec)
    end
  end')
  
  ems.object_send('resize_disk', vm_base, disk_number, new_disk_size_in_kb)
end

begin
  # dump all root attributes to the log
  dump_root() if @DEBUG
  
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
  error("vm not found")                 if vm.blank?
  error("Invalid vendor: #{vm.vendor}") unless vm.vendor.downcase == 'vmware' # This method only works with VMware VMs currently
  error("options not found")            if options.blank?
  
  # get parameters
  disk_number = options['dialog_disk_number'] || options[:dialog_disk_number] || options['disk_number'] || options[:disk_nubmer] || 1
  disk_size   = options['dialog_disk_size']   || options[:dialog_disk_size]   || options['disk_size']   || options[:disk_size]
  error("disk_number not found") if disk_number.nil?
  error("disk_size not found")   if disk_size.nil?

  disk_number = disk_number.to_i
  error("Invalid Disk Number: #{disk_number}") if disk_number.zero?

  disk_size = disk_size.to_i
  error("Invalid Disk Size: #{disk_number}") if disk_size <= 0
  disk_size_kb = disk_size * (1024**2)
  
  $evm.log(:info, "vm           => #{vm.name}")      if @DEBUG
  $evm.log(:info, "vendor       => #{vm.vendor}")    if @DEBUG
  $evm.log(:info, "disk_number  => #{disk_number}")  if @DEBUG
  $evm.log(:info, "disk_size    => #{disk_size}")    if @DEBUG
  $evm.log(:info, "disk_size_kb => #{disk_size_kb}") if @DEBUG
  
  # resize disk
  begin
    disk_number -= 1 # Subtract 1 from the disk_number since VMware starts at 0 and CFME start at 1
    resizeDisk(vm, disk_number, disk_size_kb)
  rescue => e
    if e.message =~ /VimFault/
      $evm.log(:warn, "Encountered VimFault: #{e.inspect}")
      automate_retry(30, "Encountered VimFault #{e.inspect}")
    end

    $evm.log(:error, "e: #{e}")
    $evm.log(:error, "e.inspect: #{e.inspect}")
    $evm.log(:error,"[#{e}]\n#{e.backtrace.join("\n")}")
    error(e.message)
  end
rescue => err
  error("[#{err}]\n#{err.backtrace.join("\n")}")
end
