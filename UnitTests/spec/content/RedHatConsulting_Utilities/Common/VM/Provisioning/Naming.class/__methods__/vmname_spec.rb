
#
# Efforts were made to pull up Infrastructure/.../vmname.rb & Cloud/.../vmname.rb, but did not happen
# The test suite here remains as it would apply when I get around to solving above (or testing them independentl)
#

# require_domain_file
#
# describe RedHatConsulting_Utilities::Automate::Common::VM::Provisioning::Naming::VmName do
#
#   $config = { 'vmware_folder' => '/foo', 'vm_name_suffix_counter_length' => 3 }
#
#   # let(:template) { FactoryGirl.create(:template) }
#
#   let(:flavor)        { FactoryGirl.create(:flavor, :name => 'flavor1', :cloud_subnet_required => true) }
#   let(:ems)           { FactoryGirl.create(:ems_amazon_with_authentication) }
#   let(:vm_template)   { FactoryGirl.create(:template_amazon, :ext_management_system => ems) }
#   let(:prov_options) { { :src_vm_id => vm_template.id, :instance_type => flavor.id } }
#   let(:provision) { FactoryGirl.create(:miq_provision, :options => prov_options) }
#
#   # let(:provision) { MiqProvision.new }
#   let(:root_object) { Spec::Support::MiqAeMockObject.new.tap { |ro| ro["miq_provision"] = provision } }
#   let(:service) { Spec::Support::MiqAeMockService.new(root_object).tap { |s| s.object = { 'vm_prefix' => "abc" } } }
#   let(:classification) { FactoryGirl.create(:classification, :tag => tag, :name => "environment") }
#   let(:classification2) do
#     FactoryGirl.create(:classification,
#                        :tag => tag2,
#                        :parent => classification,
#                        :name => "prod")
#   end
#   let(:tag) { FactoryGirl.create(:tag, :name => "/managed/environment") }
#   let(:tag2) { FactoryGirl.create(:tag, :name => "/managed/environment/production") }
#
#   context "when naming a vm" do
#     before do
#       allow(provision).to receive(:get_source).and_return(vm_template)
#       allow(service).to receive(:instantiate).and_return($config)
#     end
#
#     it "no vm name from dialog" do
#       provision.update_attributes!(:options => { :number_of_vms => 200 })
#
#       described_class.new(service).main
#
#       expect(service.object['vmname']).to eq('abc$n{3}')
#     end
#
#     it "vm name from dialog" do
#       provision.update_attributes!(:options => { :number_of_vms => 200, :vm_name => "drew" })
#
#       described_class.new(service).main
#
#       expect(service.object['vmname']).to eq('drew$n{3}')
#     end
#
#     it "use model and environment tag" do
#       provision.update_attributes!(:options => { :number_of_vms => 200, :vm_tags => [classification2.id] })
#
#       described_class.new(service).main
#
#       expect(service.object['vmname']).to eq('abcpro$n{3}')
#     end
#
#     it "provisions single vm" do
#       provision.update_attributes!(:options => { :number_of_vms => 1 })
#
#       described_class.new(service).main
#
#       expect(service.object['vmname']).to eq('abc$n{3}')
#     end
#
#     it "domain_name works" do
#       provision.update_attributes!(:options => { :number_of_vms => 1, :domain_name => 'yoyodyne.com' })
#
#       described_class.new(service).main
#
#       expect(service.object['vmname']).to eq('abc$n{3}.yoyodyne.com')
#     end
#   end
# end
