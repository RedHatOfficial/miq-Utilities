module RedHatConsulting_Utilities
  module StdLib
    module Corexxx
      #*sigh*
    end
  end
end

shared_examples_for "Core StdLib" do
  # dump_root = instance_double("dump_root")
  before { allow_any_instance_of(described_class).to receive(:dump_root) {
    # Stub implementation here
  }}
  before { allow_any_instance_of(described_class).to receive(:log) }
end
