require "rails_helper"

RSpec.describe Ai::Agent::Tools::CompleteCheckin do
  let(:organization) { create(:organization) }
  let(:conversation) { create(:conversation, organization: organization, slack_channel_id: "C1") }
  let(:owner) { create(:user, organization: organization, provider_uid: "U_OWNER") }
  let(:goal) { create(:goal, organization: organization, owners: [ owner ]) }
  let!(:metric) { create(:metric, goal: goal) }
  let(:checkin) { create(:checkin, organization: organization, user: owner, goal: goal, status: "notified") }
  let(:user) { owner }
  let(:context) do
    Ai::Agent::ToolContext.new(conversation: conversation, organization: organization, user: user, agent_run: nil)
  end
  let(:tool) { described_class.new(context) }

  it "completes the given checkin(s), stamping completed_at" do
    result = tool.execute(checkin_ids: [ checkin.id ])

    expect(checkin.reload).to be_status_completed
    expect(checkin.completed_at).to be_present
    expect(result[:completed_checkin_ids]).to eq([ checkin.id ])
  end

  it "completes multiple checkins in one call" do
    initiative = create(:initiative, goal: goal)
    other_checkin = create(:checkin, organization: organization, user: owner, goal: goal,
                           initiative: initiative, status: "notified")

    result = tool.execute(checkin_ids: [ checkin.id, other_checkin.id ])

    expect(result[:completed_checkin_ids]).to contain_exactly(checkin.id, other_checkin.id)
    expect(checkin.reload).to be_status_completed
    expect(other_checkin.reload).to be_status_completed
  end

  it "accepts string ids (as an LLM tool call would send)" do
    result = tool.execute(checkin_ids: [ checkin.id.to_s ])

    expect(result[:completed_checkin_ids]).to eq([ checkin.id ])
  end

  it "returns an error, without completing anything, for a checkin belonging to another user (org-scoping: not found)" do
    other_org_checkin = create(:checkin)

    result = tool.execute(checkin_ids: [ other_org_checkin.id ])

    expect(result[:error]).to include("No open check-in found")
    expect(other_org_checkin.reload).to be_status_pending
  end

  it "returns an error, without completing anything, for a checkin belonging to a different user in the SAME org" do
    stranger = create(:user, organization: organization)
    stranger_checkin = create(:checkin, organization: organization, user: stranger, goal: goal, status: "notified")

    result = tool.execute(checkin_ids: [ stranger_checkin.id ])

    expect(result[:error]).to include("No open check-in found")
    expect(stranger_checkin.reload).to be_status_notified
  end

  it "returns an error for an empty checkin_ids list" do
    result = tool.execute(checkin_ids: [])

    expect(result).to eq(error: "No checkin_ids given.")
  end

  it "returns an error hash instead of raising on internal failure" do
    allow(context.user).to receive(:checkins).and_raise(StandardError, "boom")

    result = tool.execute(checkin_ids: [ checkin.id ])

    expect(result[:error]).to include("boom")
  end
end
