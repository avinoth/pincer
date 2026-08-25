require "rails_helper"

RSpec.describe Ai::Agent::Tools::ForgetMemory do
  let(:organization) { create(:organization) }
  let(:conversation) { create(:conversation, organization: organization) }
  let(:user) { create(:user, organization: organization) }
  let(:context) do
    Ai::Agent::ToolContext.new(conversation: conversation, organization: organization, user: user, agent_run: nil)
  end
  let(:tool) { described_class.new(context) }

  it "deactivates (never destroys) an organization-scoped memory" do
    memory = create(:memory, organization: organization, user: nil)

    result = tool.execute(memory_id: memory.id)

    expect(result).to eq(forgotten: true, memory_id: memory.id)
    expect(memory.reload).not_to be_active
    expect(Memory.exists?(memory.id)).to be true
  end

  it "lets any org member deactivate an organization-scoped memory" do
    memory = create(:memory, organization: organization, user: nil)
    other_user = create(:user, organization: organization)
    other_context = Ai::Agent::ToolContext.new(
      conversation: conversation, organization: organization, user: other_user, agent_run: nil,
    )

    result = described_class.new(other_context).execute(memory_id: memory.id)

    expect(result[:forgotten]).to be true
    expect(memory.reload).not_to be_active
  end

  it "forbids deactivating another user's user-scoped memory" do
    other_user = create(:user, organization: organization)
    memory = create(:memory, organization: organization, user: other_user)

    result = tool.execute(memory_id: memory.id)

    expect(result[:error]).to be_present
    expect(memory.reload).to be_active
  end

  it "returns an error string, not an exception, when the memory isn't found" do
    result = tool.execute(memory_id: -1)

    expect(result[:error]).to be_present
  end

  it "returns an error hash instead of raising on internal failure" do
    allow(Memory).to receive(:where).and_raise(StandardError, "boom")

    result = tool.execute(memory_id: 1)

    expect(result).to eq(error: "Couldn't forget memory 1: boom")
  end
end
