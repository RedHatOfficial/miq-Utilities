# Get all the tags for a given tag caegory for use in a dynamic drop down list.
#
# Is dynamically visible depending on if the given multiselect value matches the given tag category single value setting.
#   Visible if:
#     * this element is multiselect and the selected tag category is not a single value
#     * this element is not multiselect and the selected tag category is single value
#   NOT visible if
#     * this element is multiselect and the selected tag catetgory is single value
#     * this element is not multiselect and the selected tag category is not single value
#
# Parameters:
#   tag_category     String
#     * $evm.inputs
#     * $evm.root
#   multiselect      Boolean Used to determine if this element shoudl be visible or not
#
@DEBUG = false

# Gets all of the Tags in a given Tag Category
#
# @param category Tag Category to get all of the Tags for
#
# @return Hash of Tag names mapped to Tag descriptions
#
# @source https://pemcg.gitbooks.io/mastering-automation-in-cloudforms-4-2-and-manage/content/using_tags_from_automate/chapter.html#_getting_the_list_of_tags_in_a_category
def get_category_tags(category)
  classification = $evm.vmdb(:classification).find_by_name(category)
  tags = {}
  $evm.vmdb(:classification).where(:parent_id => classification.id).each do |tag|
    tags[tag.name] = tag.description
  end
  
  return tags
end

begin
  # If there isn't a vmdb_object_type yet just exit. The method will be recalled with an vmdb_object_type
  exit MIQ_OK unless $evm.root['vmdb_object_type']
  
  # find selected tag category
  if $evm.inputs['tag_category'] && $evm.inputs['tag_category'] != "nil"
    tag_category = $evm.inputs['tag_category']
  else
    tag_category = $evm.root['dialog_tag_category']
  end
  $evm.log(:info, "tag_category => #{tag_category}") if @DEBUG

  if !tag_category.blank?
    # determine if this element should be visibile
    classification = $evm.vmdb(:classification).find_by_name(tag_category)
    single_value   = classification.single_value
    multiselect    = $evm.inputs['multiselect']
    always_visible = $evm.inputs['always_visible']
    visible        = (single_value == !multiselect) || always_visible
    
    $evm.log(:info, "single_value   => #{single_value}") if @DEBUG
    $evm.log(:info, "multiselect    => #{multiselect}")  if @DEBUG
    $evm.log(:info, "always_visible => #{always_visible}")  if @DEBUG
    $evm.log(:info, "visibile       => #{visible}")      if @DEBUG
  
    # determine tags to display
    if !visible || tag_category.nil? || tag_category.length.zero?
      tags = {}
    else
      tags = get_category_tags(tag_category)
    end
  else
    visible = false
    tags    = {}
  end
  
  # create dialog element
  dialog_field = $evm.object
  dialog_field["sort_by"]    = "value"
  dialog_field["sort_order"] = "ascending"
  dialog_field["data_type"]  = "string"
  dialog_field["visible"]    = visible
  dialog_field["values"]     = tags
  
  $evm.log(:info, "tags => #{tags}") if @DEBUG
end
