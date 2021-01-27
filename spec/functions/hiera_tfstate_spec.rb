require 'spec_helper'
require 'puppet/functions/hiera_tfstate'

#describe 'hiera_tfstate' do
describe 'hiera_tfstate' do

  let(:function) { described_class.new }

  before(:each) do
    @context = instance_double("Puppet::LookupContext")
    allow(@context).to receive(:cache_has_key)
    allow(@context).to receive(:explain)
    allow(@context).to receive(:interpolate) do |val|
      val
    end
    allow(@context).to receive(:cache)
    allow(@context).to receive(:not_found)
    allow(@context).to receive(:interpolate).with('/path').and_return('/path')
    @options = {'backend': 'file', 'statefile': '/tmp/terraform.tfstate' }
  end

  describe "#data_hash" do
    context "should run" do
      it { is_expected.to run.with_params(@options, @context) }
    end
  end
end
