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
        miq_request = get_request rescue nil
        @handle.log(level, "#{msg}")
        miq_request.user_message = msg if miq_request && (update_message || level.to_s == 'error')
      end

      def dump_thing(thing)
        log(:info, "Begin @handle.#{thing}.attributes")
        @handle.send(thing).attributes.sort.each { |k, v|
          log(:info, "\t Attribute: #{k} = #{v.inspect}")
        }
        log(:info, "End @handle.#{thing}.attributes")
        log(:info, "")
      end

      def dump_root()
        dump_thing('root')
      end

      def dump_object()
        dump_thing('object')
      end

      def dump_all()
        %w(root object parent).each do |thing|
          dump_thing(thing) if @handle.send(thing) rescue nil
        end

      end

      def error(msg)
        @handle.log(:error, msg)
        @handle.root['ae_result'] = 'error'
        @handle.root['ae_reason'] = msg.to_s
        exit MIQ_STOP
      end

      def get_provider(provider_id = nil)
        unless provider_id.nil?
          @handle.root.attributes.detect { |k, v| provider_id = v if k.end_with?('provider_id') } rescue nil
        end
        provider = @handle.vmdb(:ManageIQ_Providers_Amazon_CloudManager).find_by_id(provider_id)
        log(:info, "Found provider: #{provider.name} via provider_id: #{provider.id}") if provider

        # set to true to default to the fist amazon provider
        use_default = true
        unless provider
          # default the provider to first openstack provider
          provider = @handle.vmdb(:ManageIQ_Providers_Amazon_CloudManager).first if use_default
          log(:info, "Found amazon: #{provider.name} via default method") if provider && use_default
        end
        provider ? (return provider) : (return nil)
      end

      def set_complex_state_var(name, value)
        @handle.set_state_var(name.to_sym, JSON.generate(value))
      end

      def get_complex_state_var(name)
        JSON.parse(@handle.get_state_var(name.to_sym))
      end

      # Useful in the rescue of service provisioning methods.
      # rescue => err
      #   handle_service_error(err)
      # end
      def handle_service_error(err)
        log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
        task = get_stp_task
        miq_request = task.miq_request unless task.nil?
        current_state = @handle.root['ae_state']
        current_state ||= @handle.current_method
        miq_request.user_message = "#{current_state} failed #{err}" unless miq_request.nil?
        task['status'] = 'Error' if task
        task.finished("#{err}") if task
        exit MIQ_ABORT
      end

      def get_stp_task
        task = @handle.root['service_template_provision_task']
        raise 'service_template_provision_task not found' unless task
        task
      end

      def get_request
        miq_request = @handle.vmdb(:miq_request).find_by_id(get_stp_task.miq_request_id)
        raise 'miq_request not found' unless miq_request
        miq_request
      end

      def get_service
        service = get_stp_task.destination
        raise 'service not found' unless service
        service
      end

      # Useful for Ansible Service Provisioning.
      def get_extra_vars
        extra_vars = get_service.job_options[:extra_vars]
        log(:info, "extra_vars: #{extra_vars.inspect}")
        extra_vars
      end

      def set_extra_vars(extra_vars)
        service = get_service

        # Remove any keys with blank values from extra_vars.
        extra_vars.delete_if { |k, v| v == '' }

        # Save updated job_options to service.
        job_options = service.job_options
        job_options[:extra_vars] = extra_vars
        service.job_options = job_options
        log(:info, "extra_vars updated: #{service.job_options[:extra_vars].inspect}")
      end

    end
  end
end
