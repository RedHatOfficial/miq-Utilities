# Get all of the tag categories for use in a dynamic drop down list.

@DEBUG = false

begin
  tag_categories = {}
  tag_categories[nil] = nil
  $evm.vmdb(:classification).categories.each do |category|
    tag_categories[category.name] = category.description
  end
  
  dialog_field = $evm.object
  dialog_field["sort_by"]    = "value"
  dialog_field["sort_order"] = "ascending"
  dialog_field["data_type"]  = "string"
  dialog_field["values"]     = tag_categories
  
  $evm.log(:info, "tag_categories => #{tag_categories}") if @DEBUG
end
