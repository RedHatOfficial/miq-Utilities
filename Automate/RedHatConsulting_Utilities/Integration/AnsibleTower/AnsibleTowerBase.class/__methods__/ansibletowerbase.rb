# Author: Brant Evans    (bevans@redhat.com)
# Author: Jeffrey Cutter (jcutter@redhat.com
# Author: Andrew Becker  (anbecker@redhat.com)
# License: GPL v3
#
# Base Class for interating with Ansible Tower
#
module Integration
  module AnsibleTower
    class AnsibleTowerBase

      include RedHatConsulting_Utilities::StdLib::Core

      require 'rest_client'
      require 'json'
      require 'cgi'

      TOWER_CONFIGURATION_URI = 'Integration/AnsibleTower/Configuration/default'.freeze

      attr_reader :tower_inventory_name, :tower_inventory_id

      def initialize( handle = $evm )
        @handle = handle
        @DEBUG = false
        @tower_config = @handle.instantiate(TOWER_CONFIGURATION_URI)
        validate_tower_configuration
        log(:info, "Resolved Ansible Tower Configuration URI: #{@tower_config.name}") if @DEBUG
        @tower_inventory_name  = @tower_config['tower_inventory_name']
        @tower_inventory_id    = determine_tower_inventory_id
      end

      def validate_tower_configuration
        log(:info, "Ansible Tower Configuration => #{@tower_config.attributes}") if @DEBUG
        config_invalid = false
        begin
          tower_uri        = URI.parse( @tower_config['tower_url'] )
          config_invalid ||= tower_uri.scheme.nil?
          config_invalid ||= tower_uri.host.nil?
        rescue
          config_invalid = true
        end
        config_invalid ||= @tower_config['tower_username'].nil?
        config_invalid ||= @tower_config['tower_password'].nil?
        config_invalid ||= @tower_config['tower_verify_ssl'].nil?
        config_invalid ||= @tower_config['tower_api_timeout'].nil?
        config_invalid ||= @tower_config['tower_api_version'].nil?
        config_invalid ||= @tower_config['tower_inventory_name'].nil?
        if config_invalid
          error( "Tower Configuration invalid. Examine configuration at #{@tower_config.name}" )
        end
      end

      # Ansible Tower has specific requirements for the path portion of a URL
      # This methods enforces those requirements
      def build_tower_request_url(api_path)
        api_version = @tower_config['tower_api_version']
        tower_url = @tower_config['tower_url']
        # build the URL for the REST request
        url = "#{tower_url}/api/#{api_version}/#{api_path}"
        # Tower expects the api path to end with a "/" so guarantee that it is there
        # Searches and filters don't like trailing / so exclude if includes =
        url << '/' unless url.end_with?('/') || url.include?('=')
        log(:info, "URL Built for Tower API Call: < #{url} >") if @DEBUG
        return url
      end

      def tower_request(action, api_path, payload=nil)
        params = {
          :method     => action,
          :url        => build_tower_request_url(api_path),
          :user       => @tower_config['tower_username'],
          :password   => @tower_config['tower_password'],
          :verify_ssl => @tower_config['tower_verify_ssl'],
          :timeout    => @tower_config['tower_api_timeout']
        }
        params[:payload] = payload unless payload.nil?
        params[:headers] = {:content_type => 'application/json' } unless payload.nil?
        @handle.log(:info, "Tower request payload: #{payload.inspect}") if (@DEBUG and !payload.nil?)

        response = RestClient::Request.new(params).execute
        log(:info, "Tower Response Code => #{response.code}") if @DEBUG
        log(:info, "Tower Response => #{response.to_s}") if @DEBUG
        response_json = JSON.parse(response) unless ( response.body.nil? or response.body.empty? )
        return response_json
      end

      # Generate the host's name that will be used in an inventory
      # More information about the inventory_hostname variable in Anisble
      # - https://docs.ansible.com/ansible/latest/user_guide/playbooks_variables.html#accessing-information-about-other-hosts-with-magic-variables
      #
      #
      # @param vm object
      def inventory_hostname( vm )
        vm_hostname   = vm.hostnames.first unless vm.hostnames.nil? or vm.hostnames.empty?
        vm_hostname ||= vm.name
        error( 'Unable to determine VM Hostname for Ansible Tower Inventory') if ( vm_hostname.nil? or vm_hostname.empty? )
        @handle.log(:info, "VM Hostname determined for Ansible Tower Inventory: #{vm_hostname}") if @DEBUG
        return vm_hostname
      end

      # Determine Internal Ansible Tower Inventory ID based on Tower Inventory Name
      def determine_tower_inventory_id
        api_path = "inventories?name=#{CGI.escape(@tower_inventory_name)}"
        inventory_result = tower_request(:get, api_path)
        inventory_id = inventory_result['results'].first['id'] rescue nil
        error( "Unable to determine Ansible Tower Inventory ID from Inventory Name [ #{@tower_inventory_name} ]") if inventory_id.nil?
        log(:info, "Inventory ID determined from Inventory name: [ #{@tower_inventory_name} ] --> ID: [ #{@tower_inventory_id} ]") if @DEBUG
        return inventory_id
      end

      # Determine if a VM currently exists in the configured Ansible Tower Inventory
      # Based on the determined inventory_hostname of the VM
      #
      # @param vm object
      def vm_in_inventory?( vm )
        api_path = "inventories/#{@tower_inventory_id}/hosts?name=#{inventory_hostname( vm )}"
        result = tower_request(:get, api_path)
        return result['count'] != 0
      end
      
      # Determine the host id for a host in a Tower inventory
      # returns nil if the host is not in the inventory
      #
      # @param vm object
      def tower_host_id( vm )
        api_path = "inventories/#{@tower_inventory_id}/hosts?name=#{inventory_hostname( vm )}"
        result = tower_request(:get, api_path)
        result['count'] != 0 ? result['results'].first['id'] : nil
      end
      
    end
  end
end
