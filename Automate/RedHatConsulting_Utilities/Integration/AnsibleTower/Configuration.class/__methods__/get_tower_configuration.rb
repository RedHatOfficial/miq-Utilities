# Get the required Tower configuration from configured Ansible Tower provider
#
# @return tower_url
# @return tower_username
# @return tower_password 
# @return tower_verify_ssl
@DEBUG = false

begin
  tower_provider = $evm.vmdb(:ManageIQ_Providers_AnsibleTower_Provider).first  
  if !tower_provider.nil?
    $evm.object['tower_username']   = tower_provider.object_send(:authentication_userid)
    $evm.object['tower_password']   = tower_provider.object_send(:authentication_password)
    tower_uri = URI(tower_provider.object_send(:url))
    $evm.object['tower_url']       = "#{tower_uri.scheme}://#{tower_uri.host}"
    $evm.object['tower_verify_ssl'] = tower_provider.object_send(:verify_ssl) == 1
  end
end
