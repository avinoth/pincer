require "rails_helper"

RSpec.describe Ai::Agent::Tools do
  describe ".registry" do
    it "contains every registered tool" do
      expect(described_class.registry).to contain_exactly(
        Ai::Agent::Tools::ShowGoalCreateForm,
        Ai::Agent::Tools::ListGoals,
        Ai::Agent::Tools::GetGoal,
        Ai::Agent::Tools::SaveMemory,
        Ai::Agent::Tools::ForgetMemory,
        Ai::Agent::Tools::EditGoal,
        Ai::Agent::Tools::PickGoal,
        Ai::Agent::Tools::ShowGoals,
        Ai::Agent::Tools::ShowGoal,
        Ai::Agent::Tools::CreateInitiative,
        Ai::Agent::Tools::ShowInitiativeCreateForm,
        Ai::Agent::Tools::PickInitiative,
        Ai::Agent::Tools::EditInitiative,
        Ai::Agent::Tools::DeleteInitiative,
        Ai::Agent::Tools::RecordMetricUpdate,
        Ai::Agent::Tools::UpdateInitiativeStatus,
        Ai::Agent::Tools::AddGoalUpdate,
        Ai::Agent::Tools::CompleteCheckin,
      )
    end
  end

  describe ".build_all" do
    it "instantiates every registered tool bound to the given context" do
      conversation = create(:conversation)
      context = Ai::Agent::ToolContext.new(
        conversation: conversation,
        organization: conversation.organization,
        user: create(:user, organization: conversation.organization),
        agent_run: create(:agent_run, conversation: conversation),
      )

      tools = described_class.build_all(context)

      expect(tools.map(&:class)).to match_array(described_class.registry)
      expect(tools).to all(be_a(Ai::Agent::Tools::Base))
      expect(tools.map(&:context)).to all(eq(context))
    end
  end

  describe "PENDING" do
    it "is a stable sentinel value" do
      expect(described_class::PENDING).to eq(:pending_human)
    end
  end
end
