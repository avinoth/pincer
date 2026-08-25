require "rails_helper"

RSpec.describe AgentRun do
  it { is_expected.to belong_to(:conversation) }
  it { is_expected.to have_many(:llm_calls) }

  it { is_expected.to validate_presence_of(:status) }

  it do
    is_expected.to define_enum_for(:status)
      .with_values(
        running: "running",
        paused_on_tool: "paused_on_tool",
        completed: "completed",
        failed: "failed")
      .backed_by_column_of_type(:string)
      .with_prefix("status")
  end

  it "defaults to running" do
    run = create(:agent_run)
    expect(run).to be_status_running
  end

  describe ".paused_on_tool" do
    it "returns only runs paused on a tool call" do
      paused = create(:agent_run, status: "paused_on_tool")
      create(:agent_run, status: "running")

      expect(described_class.paused_on_tool).to contain_exactly(paused)
    end
  end

  it "nullifies llm_calls when destroyed" do
    run = create(:agent_run)
    llm_call = create(:llm_call, organization: run.conversation.organization, agent_run: run)

    run.destroy

    expect(llm_call.reload.agent_run_id).to be_nil
  end
end
