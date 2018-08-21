require_domain_file

describe RedHatConsulting_Utilities::Automate::System::CommonMethods::TaggingMethods::AddTagToLans do

  let(:tag) { FactoryGirl.create(:tag, :name => "/managed/environment/qa") }
  let(:tag2) { FactoryGirl.create(:tag, :name => "/managed/environment/production") }

  # FactoryGirl.define do
  #   factory :ems_vmware_with_hosts do
  #     after :create do |x|
  #       x.hosts += [FactoryGirl.create(:host),FactoryGirl.create(:host),]
  #     end
  #   end
  # end

  let(:ems) do
    FactoryGirl.create(:ems_vmware_with_valid_authentication) do |e|
      e.hosts = []
      e.hosts << host1
      e.hosts << host2
    end
  end

  let(:root_object) do
    Spec::Support::MiqAeMockObject.new(attributes)
  end

  let(:ae_service) do
    Spec::Support::MiqAeMockService.new(root_object).tap do |service|
      current_object = Spec::Support::MiqAeMockObject.new
      current_object.parent = root_object
      service.object = current_object
    end
  end

  let(:lan1) { FactoryGirl.create(:lan) }
  let(:lan2) { FactoryGirl.create(:lan) }
  let(:cluster) { FactoryGirl.create(:ems_cluster) }
  let(:host1) { FactoryGirl.create(:host, ems_cluster: cluster, lans: [lan1, lan2]) }
  let(:host2) { FactoryGirl.create(:host, ems_cluster: cluster, lans: [lan1, lan2]) }
  let(:rp1) { FactoryGirl.create(:resource_pool) }
  let(:rp2) { FactoryGirl.create(:resource_pool) }

  context 'tagging vlans' do

    let(:attributes) do
      {
        'vmdb_object_type' => 'ext_management_system',
        'ext_management_system' => ems,
        'dialog_multiselect_tags' => ["environment/qa", "environment/production"],
        'single_value_tag_name' => "environment/qa"
      }
    end

    # let(:storages) { 4.times.collect { |r| FactoryGirl.create(:storage, :free_space => 1000 * (r + 1)) } }
    # let(:ro_storage) { FactoryGirl.create(:storage, :free_space => 10000) }
    # let(:vms) { 5.times.collect { FactoryGirl.create(:vm_vmware) } }
    #
    # let(:host1) { FactoryGirl.create(:host_vmware, :storages => storages[0..1], :vms => vms[2..3], :ext_management_system => ems) }
    # let(:host2) { FactoryGirl.create(:host_vmware, :storages => storages[0..1], :vms => vms[2..4], :ext_management_system => ems) }
    #
    # let(:host_struct) do
    #   [MiqHashStruct.new(:id => host1.id, :evm_object_class => host1.class.base_class.name.to_sym),
    #    MiqHashStruct.new(:id => host2.id, :evm_object_class => host2.class.base_class.name.to_sym)]
    # end


    it 'tags when given a ext_management_system' do
      # allow(ae_service).to receive(:create_notification)


      # JeffW:  This is doing nothing here, but I'll leave the file and the
      #         mostly obvious stuff above mocking out models that have
      #         bidirectional links (hosts<-->lan) is somewhere between tricky
      #         and impossible, I'll come back to it.

      #described_class.new(ae_service).main

    end
  end

end
