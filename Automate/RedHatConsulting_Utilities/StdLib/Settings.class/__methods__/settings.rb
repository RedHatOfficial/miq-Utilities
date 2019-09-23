#  settings.rb
#
# To provide a unified view of Settings, copy this (unchanged) to the very highest priority Automate Domain
# From the GUI, configure Embedded Methods for settingsstore from the domains you care about (with domain prefix included).
#
# Domain priority (and embedded method entry order) will be ignored, but the configurable PRIORITY is used when merging
# building the merged settings with PRIORITY 0 being the highest.

require 'deep_merge'
require 'active_support/time'

#  Author: Jeff Warnica <jwarnica@redhat.com> 2018-08-16
#
# Provides a common location for settings for RedHatConsulting_Utilities,
# and some defaults for the children project like rhc-miq-quickstart
#
# Settings are Global, Default, and by RegionID, with regional settings falling through to Default
#-------------------------------------------------------------------------------
#   Copyright 2018 Jeff Warnica <jwarnica@redhat.com>
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#-------------------------------------------------------------------------------
module RedHatConsulting_Utilities
  module StdLib
    module Core

      # Settings handles storage and access of, er, settings. These can be Global, or bound to a RegionID, or a default
      # in the cases where there are no specific region settings.
      class Settings

        PRIORITY = 0

        SETTINGS = {}.freeze

        ##
        # Gets setting from our configuration hash above
        #
        # == Parameters:
        # region:
        #   A string which is a region number, or the symbol :global
        # key:
        #   The key to fetch from the selected region, or default if the key is not found in the region
        # default:
        #   if set, the default value to return if a key is not found (suppresses all errors)
        def get_setting(region, key, default = nil)
          region = ('r' + region.to_s).to_sym unless region == :global
          key = key.to_sym
          begin
            unless @real_settings.key?(region)
              raise(KeyError, "region [#{region}] does not exist in settings hash and/or no default provided for [#{key}]") unless @real_settings[:default].key?(key)
              return @real_settings[:default][key]
            end
            return @real_settings[region][key] if @real_settings[region].key?(key)
            raise(KeyError, "key [#{key}] does not exist in region [#{region}] or defaults settings hash, and/or no default provided") unless @real_settings[:default].key?(key)
            return @real_settings[:default][key]
          rescue KeyError => e
            raise e if default.nil?
            return default
          end
        end

        def get_effective_settings
          @real_settings
        end

        def initialize
          # Deep magic.
          # Get all the classes that are descendents of this (< is overloaded to compare class hierarchy)
          descendants = ObjectSpace.each_object(Class).select do |klass|
            klass < RedHatConsulting_Utilities::StdLib::Core::Settings
          end
          $evm.log(:info, "settings descendants unsorted order: [#{descendants}]")

          # sort them by priority (reverse! 0 is highest)
          descendants.sort! { |a, b| a::PRIORITY <=> b::PRIORITY }
          $evm.log(:info, "settings descendants   sorted order: [#{descendants}]")

          @real_settings = {}
          settings_from = []
          settings_from << [0, self.class]
          @real_settings.deep_merge!(SETTINGS)
          descendants.each do |s|
            settings_from << [s::PRIORITY, s]
            @real_settings.deep_merge!(s::SETTINGS)
          end
          @real_settings[:settings_from] = settings_from
        end
      end
    end
  end
end

# testing code here
#
# Uncomment to test from commandline or ide
# leave the middle bit uncommented for use in Automate
# TEST TEST TEST BEGIN

#
# module Foo
#   class Settings < RedHatConsulting_Utilities::StdLib::Core::Settings
#     PRIORITY = 10
#     SETTINGS = {
#       global: {
#         from_settings: 'foo',
#         vm_auto_start: false
#       },
#
#       default: {
#         network_redhat: '<VM Network>',
#         retirement_max_extensions: 17,
#
#         in_default_not_region: 'IM FROM DEFAULT',
#       }
#     }.freeze
#   end
# end
#
# module Blargh
#   class Settings < RedHatConsulting_Utilities::StdLib::Core::Settings
#     PRIORITY = 49
#     SETTINGS = {
#       global: {
#         from_settings: 'blargh',
#       }
#     }.freeze
#   end
# end
#
# module Bar
#   class Settings < RedHatConsulting_Utilities::StdLib::Core::Settings
#     PRIORITY = 15
#     SETTINGS = {
#       global: {
#         from_settings: 'bar',
#       }
#     }.freeze
#   end
# end
#
# module Baz
#   class Settings < RedHatConsulting_Utilities::StdLib::Core::Settings
#     PRIORITY = 3
#     SETTINGS = {
#       global: {
#         from_settings: 'baz',
#       }
#     }.freeze
#   end
# end

#TEST TEST TEST TEST END


if __FILE__ == $PROGRAM_NAME
  settings = RedHatConsulting_Utilities::StdLib::Core::Settings.new()
end


#TEST TEST TEST TEST BEGIN

# require '/home/jwarnica/RubymineProjects/miq-Utilities/Automate/RedHatConsulting_Utilities/StdLib/Settings.class/__methods__/settingsstore.rb'
#
#
# settings = RedHatConsulting_Utilities::StdLib::Core::Settings.new()
#
# puts settings.get_setting(901, :network_redhat)
# puts settings.get_setting(901, :retirement_max_extensions)
#
# x = settings.get_setting(901, :default_custom_spec) rescue "no x"
# puts x
#
# x = settings.get_setting(:global, :network_lookup_keys) rescue "no x"
# puts x
#
# @region = 901
# x = settings.get_setting(@region, 'infoblox_url')
# puts x
#
# x = settings.get_setting(@region, 'custom_obscure_setting', { a: 'b' })
# puts x
#
#
# x = settings.get_effective_settings()
# puts "effective settings: #{x}"

# begin
#   x = settings.get_setting(@region, 'custom_obscure_setting')
#   puts x
# rescue KeyError => e
#   puts "supposed to fail. All is OK: [#{e}]"
# end

#
# x = settings.get_setting(34, 'in_default_not_region')
# puts "XXXXXXXXXX"
# puts "in_default_not_region: [#{x}]"

#TEST TEST TEST TEST END

