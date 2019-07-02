#
# Description: Core.class StdLib
#
module RedHatConsulting_Utilities
  module StdLib
    module Core

      def initialize(handle = $evm)
        @handle = handle
        @task = get_stp_task rescue nil
      end

      def log(level, msg, update_message = false)
        miq_request = get_request rescue nil
        @handle.log(level, "#{msg}")
        @task.message = msg if @task && (update_message || level == 'error')
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

      # Logs all the attributes from a given attribute on $evm.root
      #
      # @param root_attribute Attribute on $evm.root to log all of the attributes for
      def dump_root_attribute(root_attribute)
        dump_thing_attribute(@handle.root, '@handle.root', root_attribute)
      end

      def dump_thing_attribute(thing, thing_name, attribute)
        log(:info, "#{thing_name}['#{attribute}'].attributes => {")
        if thing[attribute].attributes.try(:sort)
          thing[attribute].attributes.sort.each { |k, v| log(:info, "\t#{k} => #{v.inspect}") }
        else
          log(:info, '<un-dumpable object>')
        end
        log(:info, '}')
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
      
      def get_task_option_yaml_data(task, option)
        task.get_option(option).nil? ? nil : YAML.load(task.get_option(option))
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

      # There are many ways to attempt to pass parameters in Automate.
      # This function checks all of them in priorty order as well as checking for symbol or string.
      #
      # Order:
      #   1. Inputs
      #   2. Current
      #   3. Object
      #   4. Root
      #   5. State
      #
      # @return Value for the given parameter or nil if none is found
      def get_param(param)
        # check if inputs has been set for given param
        param_value ||= @handle.inputs[param.to_sym]
        param_value ||= @handle.inputs[param.to_s]

        # else check if current has been set for given param
        param_value ||= @handle.current[param.to_sym]
        param_value ||= @handle.current[param.to_s]

        # else check if current has been set for given param
        param_value ||= @handle.object[param.to_sym]
        param_value ||= @handle.object[param.to_s]

        # else check if param on root has been set for given param
        param_value ||= @handle.root[param.to_sym]
        param_value ||= @handle.root[param.to_s]

        # check if state has been set for given param
        param_value ||= @handle.get_state_var(param.to_sym)
        param_value ||= @handle.get_state_var(param.to_s)

        param_value
      end

      def get_user
        user_search = @handle.root['dialog_userid'] || @handle.root['dialog_evm_owner_id']
        user = @handle.vmdb('user').find_by_id(user_search) || @handle.vmdb('user').find_by_userid(user_search) ||
          @handle.root['user']
        user
      end

      def get_current_group_rbac_array
        rbac_array = []
        unless @user.current_group.filters.blank?
          @user.current_group.filters['managed'].flatten.each do |filter|
            next unless /(?<category>\w*)\/(?<tag>\w*)$/i =~ filter
            rbac_array << { category => tag }
          end
        end
        log(:info, "@user: #{@user.userid} RBAC filters: #{rbac_array}")
        rbac_array
      end

      def object_eligible?(obj)
        return false if obj.archived || obj.orphaned
        @rbac_array.each do |rbac_hash|
          rbac_hash.each do |rbac_category, rbac_tags|
            Array.wrap(rbac_tags).each { |rbac_tag_entry| return false unless obj.tagged_with?(rbac_category, rbac_tag_entry) }
          end
          true
        end
      end

      # Perform a method retry for the given reason
      #
      # @param seconds Number of seconds to wait before next retry
      # @param reason  Reason for the retry
      def automate_retry(seconds, reason)
        @handle.root['ae_result'] = 'retry'
        @handle.root['ae_retry_interval'] = "#{seconds.to_i}.seconds"
        @handle.root['ae_reason'] = reason

        @handle.log(:info, "Retrying #{@method} after #{seconds} seconds, because '#{reason}'") if @DEBUG
        exit MIQ_OK
      end
      
      # Set attributes to skip to specified next state
      #
      # @param message Reason for the skip
      # @param next_state State to skip to
      def skip_to_state(message, next_state)
        log(:info, "#{message}. Skip to State <#{next_state}>")
        @handle.root['ae_result']     = 'skip'
        @handle.root['ae_next_state'] = next_state
        exit MIQ_OK
      end

      # Function for getting the current VM and associated options based on the vmdb_object_type.
      #
      # Supported vmdb_object_types
      #   * miq_provision
      #   * vm
      #   * automation_task
      #
      # @return vm,options
      def get_vm_and_options()
        @handle.log(:info, "@handle.root['vmdb_object_type'] => '#{@handle.root['vmdb_object_type']}'.")
        case @handle.root['vmdb_object_type']
        when 'miq_provision'
          # get root object
          miq_provision =  @handle.root['miq_provision']

          # get VM
          vm = miq_provision.vm

          # get options
          options = miq_provision.options
          #merge the ws_values, dialog, top level options into one list to make it easier to search
          options = options.merge(options[:ws_values]) if options[:ws_values]
          options = options.merge(options[:dialog])    if options[:dialog]
        when 'vm'
          # get root objet & VM
          vm = get_param(:vm)

          # get options
          options =  @handle.root.attributes
          #merge the ws_values, dialog, top level options into one list to make it easier to search
          options = options.merge(options[:ws_values]) if options[:ws_values]
          options = options.merge(options[:dialog])    if options[:dialog]
        when 'automation_task'
          # get root objet
          automation_task =  @handle.root['automation_task']

          # get VM
          vm  = get_param(:vm)

          # get options
          options = get_param(:options)
          options = JSON.load(options)     if options && options.class == String
          options = options.symbolize_keys if options
          #merge the ws_values, dialog, top level options into one list to make it easier to search
          options = options.merge(options[:ws_values]) if options[:ws_values]
          options = options.merge(options[:dialog])    if options[:dialog]
        when 'service_template_provision_task'
          task = @handle.root['service_template_provision_task']

          # if service task then no VM yet
          vm = nil

          # get options
          options = get_task_option_yaml_data(task, :parsed_dialog_options)
          options = options[0] if !options[0].nil?
        else
          error("Can not handle vmdb_object_type: #{@handle.root['vmdb_object_type']}")
        end

        # standerdize the option keys
        options = options.symbolize_keys()

        return vm,options
      end

      # Create a Tag  Category if it does not already exist
      #
      # @param category     Tag Category to create
      # @param description  Tag Category description.
      #                     Optional
      #                     Defaults to the `category`
      # @param single_value True if a resource can only have one tag from this category,
      #                     False if a resource can have multiple tags from this category.
      #                     Optional.
      #                     Defaults to `false`
      #
      # @source https://pemcg.gitbooks.io/mastering-automation-in-cloudforms-4-2-and-manage/content/using_tags_from_automate/chapter.html
      def create_tag_category(category, description = nil, single_value = false)
        category_name = to_tag_name(category)
        unless @handle.execute('category_exists?', category_name)
          @handle.execute('category_create',
            :name => category_name,
            :single_value => single_value,
            :perf_by_tag => false,
            :description => description || category)
        end
      end

      # Gets all of the Tags in a given Tag Category
      #
      # @param category Tag Category to get all of the Tags for
      #
      # @return Hash of Tag names mapped to Tag descriptions
      #
      # @source https://pemcg.gitbooks.io/mastering-automation-in-cloudforms-4-2-and-manage/content/using_tags_from_automate/chapter.html#_getting_the_list_of_tags_in_a_category
      def get_category_tags(category)
        classification = @handle.vmdb(:classification).find_by_name(category)
        tags = {}
        @handle.vmdb(:classification).where(:parent_id => classification.id).each do |tag|
          tags[tag.name] = tag.description
        end

        return tags
      end


      # Create a Tag in a given Category if it does not already exist
      #
      # @param category Tag Category to create the Tag in
      # @param tag      Tag to create in the given Tag Category
      #
      # @source https://pemcg.gitbooks.io/mastering-automation-in-cloudforms-4-2-and-manage/content/using_tags_from_automate/chapter.html
      def create_tag(category, tag)
        create_tag_category(category)
        tag_name = to_tag_name(tag)
        unless @handle.execute('tag_exists?', category, tag_name)
          @handle.execute('tag_create',
            category,
            :name => tag_name,
            :description => tag)
        end

        return "#{category}/#{tag_name}"
      end

      # Takes a string and makes it a valid tag name
      #
      # @param str String to turn into a valid Tag name
      #
      # @return Given string transformed into a valid Tag name
      def to_tag_name(str)
        return str.downcase.gsub(/[^a-z0-9_]+/,'_')
      end

    end
  end
end
