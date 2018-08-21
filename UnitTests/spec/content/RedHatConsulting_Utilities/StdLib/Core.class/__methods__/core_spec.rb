#
# Test cases for core.rb, our "standard library"
#

# First, read in the Automate script we are testing
require_domain_file

# Testing black magic here.
# Since core.rb doesn't define a class, let alone initialize an object, per
# "regular" Automate "methods", and the (ruby) methods are "class" (static)
# methods, but _do_ depend on Instance variables, we need to a concrete class
# to instantiate, with the most bare of details.
#
# Note also, because we are monkey patching in the class hierchy later (dummy_class.extend()), while
# super(handle) would be the right thing, it isn't possible here.
#

module RedHatConsulting_Utilities
  module StdLib
    module Core
      class DummyClass
        include RedHatConsulting_Utilities::StdLib::Core

        def initialize(handle = $evm)
          @handle = handle
        end
      end
    end
  end
end

RSpec::Matchers.define :exit_with_code do |exp_code|
  actual = nil
  match do |block|
    begin
      block.call
    rescue SystemExit => e
      actual = e.status
    end
    actual and actual == exp_code
  end
  failure_message do |block|
    "expected block to call exit(#{exp_code}) but exit" +
      (actual.nil? ? " not called" : "(#{actual}) was called")
  end
  failure_message_when_negated do |block|
    "expected block not to call exit(#{exp_code})"
  end
  description do
    "expect block to call exit(#{exp_code})"
  end
  supports_block_expectations
end

describe RedHatConsulting_Utilities::StdLib::Core do

  # Note: Don't do this. We actually want to test Core StdLib, not the super
  # dummy version of it
  # include_examples "Core StdLib"

  before(:each) do
    @dummy_class = RedHatConsulting_Utilities::StdLib::Core::DummyClass.new(ae_service)
  end

  # create a user
  let(:user) { FactoryGirl.create(:user_with_email_and_group) }

  # and the Automate shadow object
  let(:svc_model_user) { MiqAeMethodService::MiqAeServiceUser.find(user.id) }

  # a provider
  let(:ems) { FactoryGirl.create(:ext_management_system) }

  let(:root) do
    Spec::Support::MiqAeMockObject.new(
      'dialog_provider' => ems.id.to_s,
      'user' => svc_model_user,
      'current' => current_object
    )
  end
  let(:current_object) { Spec::Support::MiqAeMockObject.new('a' => 1, 'b' => 2) }
  let(:ae_service) do
    Spec::Support::MiqAeMockService.new(root).tap do |service|
      current_object.parent = root
      # service.attributes['current_object'] = current_object
      current = current_object
    end
  end

  let(:user)          { FactoryGirl.create(:user_with_group) }


  context 'core library' do

    it 'should log with log' do
      expect(ae_service).to receive(:log).exactly(1).times
      @dummy_class.log(:info, 'Something')
    end

    it 'dump_root should produce the right number of lines' do
      log_header_footer_count = 3
      expect(ae_service).to receive(:log).exactly(root.attributes.size + log_header_footer_count).times
      @dummy_class.dump_root()
    end

    #JeffW: Existing mocks seem to have deep issue with 'current'
    #
    # it 'should log current' do
    #   log_header_footer_count = 3
    #   #     allow(ae_service).to receive(:current).and_return(current_object)
    #   root.attributes.each{|k,v| puts "[#{k}] -> [#{v}]" }
    #   root.attributes['current'].attributes.each{|k,v| puts "[#{k}] -> [#{v}]" }
    #   expect(ae_service).to receive(:log).exactly(root.attributes['current'].attributes.size + log_header_footer_count).times
    #   @dummy_class.dump_current()
    # end

    it 'should log error exit MIQ_STOP' do
      msg = 'something broke'

      expect(ae_service).to receive(:log).exactly(1).times

      begin
        @dummy_class.error(msg)
      rescue SystemExit => e
        expect(e.status).to eq MIQ_STOP
      else
        expect(true).eq false # this should never happen
      end

    end

    it 'set_complex_state_var should json serialize something' do
      name = 'foo'
      var = ['a', { 'b' => 'c' }]
      expect(ae_service).to receive(:set_state_var).with(name.to_sym, var.to_json)
      @dummy_class.set_complex_state_var(name, var)
    end

    it 'get_complex_state_var should deserizlize json data' do
      name = 'foo'
      data = ['a', { 'b' => 'c' }]
      allow(ae_service).to receive(:get_state_var).with(name.to_sym).and_return(data.to_json)

      expect(@dummy_class.get_complex_state_var(name)).to eq(data)
    end

    it 'gets rbac array' do

    end

  end

end
