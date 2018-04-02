# / Infra / VM / Provisioning / Naming / default (vmname)

#
# Description: This is the default naming scheme
# 1. If VM Name was not chosen during dialog processing then use vm_prefix and optionally domain_name
#    from dialog else use model and [:environment] tag to generate name
# 2. Else use VM name chosen in dialog
# 3. Add 3 digit suffix to vmname if more than one VM is being provisioned unless the supplied VM name contains . (DOT) in which case it is an FQDN
#
module ManageIQ
  module Automate
    module Infrastructure
      module VM
        module Provisioning
          module Naming
            class VmName
              def initialize(handle = $evm)
                @handle = handle
                @DEBUG = false
              end

              def main
                @handle.log("info", "===START: provision_object===")                                 if @DEBUG
                provision_object.attributes.sort.each { |k, v| @handle.log("info", "\t#{k}: #{v}") } if @DEBUG
                @handle.log("info", "===END: provision_object===")                                   if @DEBUG
                
                @handle.log("info", "Detected vmdb_object_type:<#{@handle.root['vmdb_object_type']}>")
                @handle.object['vmname'] = derived_name.compact.join
                @handle.log(:info, "vmname: \"#{@handle.object['vmname']}\"")
              end

              def derived_name
                if supplied_name.present?
                  [supplied_name, suffix(true)]
                else
                  [prefix, env_tag, suffix(false), domain_name]
                end
              end

              def supplied_name
                @supplied_name ||= begin
                  vm_name = get_option(:vm_name).to_s.strip
                  vm_name unless vm_name == 'changeme'
                end
              end

              def provision_object
                @provision_object ||= begin
                  @handle.root['miq_provision_request'] ||
                  @handle.root['miq_provision']         ||
                  @handle.root['miq_provision_request_template']
                end
              end

              # Returns the name prefix (preferences model over dialog) or nil
              def prefix
                get_option(:vm_prefix).to_s.strip
              end

              # Returns the first 3 characters of the "environment" tag (or nil)
              def env_tag
                env = provision_object.get_tags[:environment]
                return env[0, 3] unless env.blank?
              end

              # Returns the name suffix (provision number)
              # or nil if provisioning only one
              # or nil if supplied name contains a . (DOT) which means the supplied name is already fully qualified
              def suffix(condensed)
                "$n{#{suffix_counter_length}}" if (get_option(:number_of_vms) > 1 && supplied_name !~ /\./) || !condensed
              end
              
              def domain_name()
                domain_name = get_option(:domain_name)
                domain_name = ".#{domain_name}" if !domain_name.nil?
                @handle.log(:info, "domain_name: \"#{domain_name}\"") if @DEBUG
                return domain_name
              end
              
              def suffix_counter_length()
                return get_option(:vm_name_suffix_counter_length) || 3
              end
              
              def get_option(option)
                option_value =
                  @handle.object[option.to_sym] ||
                  @handle.object[option.to_s] ||
                  provision_object.get_option(option.to_sym) ||
                  provision_object.get_option(option.to_s) ||
                  (provision_object.get_option(:ws_values).nil? ? nil : provision_object.get_option(:ws_values)[option.to_sym]) ||
                  (provision_object.get_option(:ws_values).nil? ? nil : provision_object.get_option(:ws_values)[option.to_s])
                
                @handle.log(:info, "{ option => '#{option}', value => '#{option_value}' }") if @DEBUG
                return option_value
              end
            end
          end
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  ManageIQ::Automate::Infrastructure::VM::Provisioning::Naming::VmName.new.main
end
