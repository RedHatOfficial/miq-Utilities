# Filter clusters, hosts, and datastores based on tags
# The only expected output from this method is a hash of tags. Each tag name can be mapped to either a single value or an array
# If a single value is passed for a tag, that value must be matched on a resource for it to be selected during placement
# If an array of values is passed, any one of those values must match on a resource
#
# NOTE: Intended to be overriden by implementers.
#
# SETS
#   EVM OBJECT
#     'placement_filters' - Hash of tag names to values that must exist for a resource to be selected in the placement process

module RedHatConsulting_Utilities
  module Automate
    module Infrastructure
      module VM
        module Provisioning
          module Placement
            class PlacementFilters
              include RedHatConsulting_Utilities::StdLib::Core

              def initialize(handle = $evm)
                @handle = handle
                @DEBUG = true
              end

              # IMPLEMENTERS: DO NOT MODIFY
              #
              # Set the filters on $evm.object
              def main
                filters = placement_filters
                log(:info, "Setting placement filters to: <#{filters}>") if @DEBUG

                @handle.object['placement_filters'] = filters
              end

              # IMPLEMENTERS: Update with business logic
              # @return hash of tags to values
              def placement_filters
                prov = @handle.root["miq_provision"]
                user = prov.miq_request.requester
                error('User not specified') if user.nil?
                normalized_ldap_group = user.normalized_ldap_group.gsub(/\W/, '_')

                # By default, look for either prov_scope all or equal to the requesting user's ldap group
                filters = {
                  prov_scope: ['all', normalized_ldap_group],
                  # category: ['array', 'of', 'values'],
                }

                filters
              end

            end
          end
        end
      end
    end
  end
end
if __FILE__ == $PROGRAM_NAME
  RedHatConsulting_Utilities::Automate::Infrastructure::VM::Provisioning::Placement::PlacementFilters.new.main()
end
