# Given a Hash of Tag Categories to Tag(s), sets those Tags on the given VM.
# This will auto generate any missing Tag Categories or Tags before applying them to the VM.
#
# NOTE: Not meant to be overriden by implimentors.
#
# EXPECTED
#   EVM STATE || EVM CURRENT || EVM OBJECT || EVM ROOT
#     :vm                   - VM to set the Custom Attributes on
#     :vm_custom_attributes - Hash of Custom Attributes to value for the given VM
#
@DEBUG = false

# Log an error and exit.
#
# @param msg Message to error with
def error(msg)
  $evm.log(:error, msg)
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = msg.to_s
  exit MIQ_STOP
end

# There are many ways to attempt to pass parameters in Automate.
# This function checks all of them in priorty order as well as checking for symbol or string.
#
# Order:
#   1. Current
#   2. Object
#   3. Root
#   4. State
#
# @return Value for the given parameter or nil if none is found
def get_param(param)  
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

# Escapes a given Tag Category or Tag name to be valid.
# 
# @param name Tag Category or Tag name to escape
#
# @return Escaped Tag Category or Tag name.
def escape_tag(tag)
  tag_name = tag.to_s.downcase.gsub(/\W/,'_')
  $evm.log(:info, "Escape '#{tag}' to '#{tag_name}'") if @DEBUG
  return tag_name
end

# Sets the given tags for the given tag category on the given VMDB object.
#
# @param object                     object to apply the tag(s) to
# @param tag_category               Tag category that the Tag belongs to to apply to the VM
# @param tags                       A single Tag or Array of Tags that belong to the given Tag category to apply to the VM
# @param overwrite_single_value_tag If True then if assigning a Tag to a single value Tag category and that Tag already exists overwrite the existing Tag.
#                                   If False then if assigning a Tag to a single value Tag category and that Tag already exists, raise an exception.
#                                   Defaults to true.
# @param overwrite_multi_value_tag  If True then unassign all Tags in the given Tag category for the given object and then assign all of the given Tags.
#                                   If False then assign all of the given Tags for the given Tag category without affecting already assigned Tags for that Tag category.
#                                   Defaults to true.
# @params create_tag_category       If True and the given Tag category does not exist, create it.
#                                   If False and given Tag category does not exist, raise an exception.
#                                   If creating a new Tag category :single_value will be set to True if tags.length == 1, else will be set to False.
#                                   Defaults to true.
# @params create_tag                If True and the given Tag does not exist in the given Tag category, create it.
#                                   If False and given Tag does not exist in the given Tag category, raise an exception.
#                                   Defaults to true.
#
# @raise TagcategoryException If Tag category does not exist but attempting to assign.
#                             If Tag category is a single value Tag category andd attempting to assign multiple Tags.
# @raise TagException        If attempting to assign single value Tag to VMDB object that already has tag assigned and overwrite_single_value_tag is false.
class TagException < Exception; end
class TagcategoryException < Exception; end
def set_object_tags(vmdb_object, tag_category, tags,
    overwrite_single_value_tag = true,
    overwrite_multi_value_tag = true,
    create_tag_category = true,
    create_tag = true)
  
  # ensure tags is an array with no duplicate values
  tags = [tags] if !tags.kind_of?(Array)
  tags.uniq!
  
  # Ensure the Tag category exists
  tag_category_name = escape_tag(tag_category)
  if !$evm.execute('category_exists?', tag_category_name)
    if create_tag_category
      single_value = tags.length == 1
      $evm.execute('category_create',
        :name         => tag_category_name,
        :description  => tag_category,
        :single_value => single_value,
        :perf_by_tag  => false)
      $evm.log(:info, "Created Tag Category { :name => '#{tag_category_name}', :description => '#{tag_category}', :single_value => #{single_value} }") if @DEBUG
    else
      raise TagcategoryException, "Tag category '#{tag_category_name}' does not exist and create_tag_category=#{create_tag_category} "\
                                  "therefor can not assign '#{tag_category_name}/#{tags}'"
    end 
  end
  
  # verify that Tag category can assign muliple tags if needed
  tag_category_obj = $evm.vmdb(:classification).find_by_name(tag_category_name)
  if tag_category_obj.single_value && tags.length > 1
    raise TagcategoryException "Tag category '#{tag_category_name}' is a single value Tag category but attempting to assign multiple Tags."
  end
  
  # If single value tag, ensure this is a new Tag or should overwrite existing Tag
  existing_tags = vmdb_object.tags(tag_category_name)
  if tag_category_obj.single_value && existing_tags.length > 0 && existing_tags[0] != escape_tag(tags[0]) && !overwrite_single_value_tag
    raise TagException, "Tag category '#{tag_category_name}' is a single value Tag category, overwrite_single_value_tag=#{overwrite_single_value_tag} "\
                        "and VMDB Object '#{vmdb_object.name}' already has Tag '#{tag_category_name}/#{existing_tags[0]}' assigned so can not overwrite "\
                        "with '#{tag_category_name}/#{escape_tag(tags[0])}.'"
  end
  
  # If multi value tag and should overwrite all existing multi value Tags remove all existing Tags for the Tag category
  if !tag_category_obj.single_value && overwrite_multi_value_tag
    existing_tags.each do |existing_tag|
      vmdb_object.tag_unassign("#{tag_category_name}/#{existing_tag}")
      $evm.log(:info, "Because overwriting existing tags for multi value tag category, "\
                      "unassign existing multi value tag '#{tag_category_name}/#{existing_tag}' from '#{vmdb_object.name}'") if @DEBUG
    end
  end
  
  # Apply each tag to the given VMDB object
  tags.each do |tag|
    tag_name = escape_tag(tag)
    
    # Ensure the Tag exists
    if !$evm.execute('tag_exists?', tag_category_name, tag_name)
      if create_tag
        $evm.execute('tag_create',
          tag_category_name,
          :name        => tag_name,
          :description => tag)
        $evm.log(:info, "Created Tag { :name => '#{tag_name}', :description => '#{tag}' }") if @DEBUG
      else
        raise TagException, "Tag '#{tag_name}' does not exist and create_tag=#{create_tag} "\
                                    "therefor can not assign '#{tag_category_name}/#{tag}'"
      end
    end
    
    # assign the tag
    vmdb_object.tag_assign("#{tag_category_name}/#{tag_name}")
    $evm.log(:info, "Assigned Tag '#{tag_category_name}/#{tag_name}' to '#{vmdb_object.name}'") if @DEBUG
  end
end

begin
  # get the parameters
  if $evm.root['miq_provision']
    $evm.log(:info, "Get VM from $evm.root['miq_provision']") if @DEBUG
    vm = $evm.root['miq_provision'].vm
  else
    $evm.log(:info, "Get VM from paramater") if @DEBUG
    vm = get_param(:vm)
  end
  error("vm parameter not found") if vm.nil?
  $evm.log(:info, "vm=#{vm.name}") if @DEBUG
  
  vm_tags = get_param(:vm_tags)
  error("vm_tags parameter not found") if vm_tags.nil?
  $evm.log(:info, "vm_tags=#{vm_tags}") if @DEBUG
  
  # set the Custom Attributes on the VM
  vm_tags.each do |tag_category, tags|
    begin
      set_object_tags(vm, tag_category, tags)
    rescue TagException => e
      $evm.log(:error, "TagException occured when attempting to tag VM '#{vm.name}', ignoring: #{e}")
    rescue TagcategoryException => e
      $evm.log(:error, "TagcategoryException occured when attempting to tag VM '#{vm.name}', ignoring: #{e}")
    end
  end
end
