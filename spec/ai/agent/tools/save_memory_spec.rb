require "rails_helper"

RSpec.describe Ai::Agent::Tools::SaveMemory do
  let(:organization) { create(:organization) }
  let(:conversation) { create(:conversation, organization: organization) }
  let(:user) { create(:user, organization: organization) }
  let(:context) do
    Ai::Agent::ToolContext.new(conversation: conversation, organization: organization, user: user, agent_run: nil)
  end
  let(:tool) { described_class.new(context) }

  it "saves an organization-scoped memory with user_id nil and the source conversation set" do
    result = tool.execute(content: "Quarters start in February", scope: "organization", category: "convention")

    memory = Memory.find(result[:memory_id])
    expect(memory.organization).to eq(organization)
    expect(memory.user).to be_nil
    expect(memory.content).to eq("Quarters start in February")
    expect(memory.category).to eq("convention")
    expect(memory.source_conversation).to eq(conversation)
    expect(result).to eq(saved: true, memory_id: memory.id, scope: "organization")
  end

  it "saves a user-scoped memory for the turn's author" do
    result = tool.execute(content: "Prefers Friday check-ins", scope: "user")

    memory = Memory.find(result[:memory_id])
    expect(memory.user).to eq(user)
    expect(memory.organization).to eq(organization)
  end

  it "returns an error for an invalid scope without raising" do
    result = tool.execute(content: "Something", scope: "team")

    expect(result[:error]).to be_present
    expect(Memory.count).to eq(0)
  end

  it "returns an error hash instead of raising on internal failure" do
    allow(Memory).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Memory.new))

    result = tool.execute(content: "Something", scope: "organization")

    expect(result).to be_a(Hash)
    expect(result[:error]).to be_present
  end
end
