#
# Description: Core.class StdLib
#
module RedHatConsulting_Utilities
  module StdLib
    module Core

      def initialize(handle = $evm)
        @handle = handle
      end

      def log(level, msg, update_message = false)
        @handle.log(level, "#{msg}")
        @handle.task.message = msg if @task && (update_message || level == 'error')
      end

      def dump_thing(thing)
        thing.attributes.sort.each { |k, v|
          log(:info, "\t Attribute: #{k} = #{v}")
        }
      end

      def dump_root()
        log(:info, "Begin @handle.root.attributes")
        dump_thing(@handle.root)
        log(:info, "End @handle.root.attributes")
        log(:info, "")
      end

      def get_provider(provider_id = nil)
        unless provider_id.nil?
          $evm.root.attributes.detect { |k, v| provider_id = v if k.end_with?('provider_id') } rescue nil
        end
        provider = $evm.vmdb(:ManageIQ_Providers_Amazon_CloudManager).find_by_id(provider_id)
        log(:info, "Found provider: #{provider.name} via provider_id: #{provider.id}") if provider

        # set to true to default to the fist amazon provider
        use_default = true
        unless provider
          # default the provider to first openstack provider
          provider = $evm.vmdb(:ManageIQ_Providers_Amazon_CloudManager).first if use_default
          log(:info, "Found amazon: #{provider.name} via default method") if provider && use_default
        end
        provider ? (return provider) : (return nil)
      end

    end
  end
end
