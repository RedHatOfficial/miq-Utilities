MIN = 2
MAX = 12

begin
  values = {}
  (MIN..MAX).each { |k| values[(k*1024)] = "#{k} GB" }
  
  dialog_field = $evm.object
  dialog_field["sort_by"]       = "value"
  dialog_field["sort_order"]    = "ascending"
  dialog_field["data_type"]     = "integer"
  dialog_field["required"]      = true
  dialog_field["values"]        = values
  dialog_field["default_value"] = MIN*1024
end
