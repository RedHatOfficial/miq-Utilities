@DEBUG = false

begin
  # If there isn't a vmdb_object_type yet just exit. The method will be recalled with a vmdb_object_type
  #exit MIQ_OK unless $evm.root['vmdb_object_type']
  
  values = {}
  $evm.vmdb('ems').all.each do |ems|
    values[ems.id] = ems.name
  end
  
  dialog_field = $evm.object
  dialog_field["sort_by"]    = "value"
  dialog_field["sort_order"] = "ascending"
  dialog_field["data_type"]  = "integer"
  dialog_field["required"]   = true
  dialog_field["values"]     = values
  
  $evm.log(:info, "values => #{values}") if @DEBUG
end
