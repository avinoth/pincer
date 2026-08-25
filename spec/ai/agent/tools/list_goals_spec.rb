require "rails_helper"

RSpec.describe Ai::Agent::Tools::ListGoals do
  let(:organization) { create(:organization) }
  let(:conversation) { create(:conversation, organization: organization) }
  let(:user) { create(:user, organization: organization) }
  let(:context) do
    Ai::Agent::ToolContext.new(conversation: conversation, organization: organization, user: user, agent_run: nil)
  end
  let(:tool) { described_class.new(context) }

  describe "period overlap filtering" do
    it "includes goals whose dates overlap the given period and excludes goals entirely outside it" do
      overlapping = create(:goal, organization: organization, start_date: "2026-06-15", end_date: "2026-07-15")
      contained = create(:goal, organization: organization, start_date: "2026-07-10", end_date: "2026-07-20")
      before_period = create(:goal, organization: organization, start_date: "2026-05-01", end_date: "2026-06-30")
      after_period = create(:goal, organization: organization, start_date: "2026-08-01", end_date: "2026-09-01")

      result = tool.execute(start_date: "2026-07-01", end_date: "2026-07-31")

      ids = result.map { |g| g[:id] }
      expect(ids).to include(overlapping.id, contained.id)
      expect(ids).not_to include(before_period.id, after_period.id)
    end

    it "applies an open-ended filter when only one bound is given" do
      early = create(:goal, organization: organization, start_date: "2026-01-01", end_date: "2026-02-01")
      late = create(:goal, organization: organization, start_date: "2026-08-01", end_date: "2026-09-01")

      result = tool.execute(start_date: "2026-07-01")

      ids = result.map { |g| g[:id] }
      expect(ids).to include(late.id)
      expect(ids).not_to include(early.id)
    end
  end

  describe "owner filtering" do
    it "resolves an owner by Slack provider_uid" do
      owner = create(:user, organization: organization, provider_uid: "U_OWNER")
      goal = create(:goal, organization: organization, owners: [ owner ])
      create(:goal, organization: organization)

      result = tool.execute(owner: "U_OWNER")

      expect(result.map { |g| g[:id] }).to contain_exactly(goal.id)
    end

    it "resolves an owner loosely by name fragment" do
      owner = create(:user, organization: organization, full_name: "Ada Lovelace")
      goal = create(:goal, organization: organization, owners: [ owner ])
      create(:goal, organization: organization)

      result = tool.execute(owner: "lovelace")

      expect(result.map { |g| g[:id] }).to contain_exactly(goal.id)
    end

    it "returns no goals when the owner can't be resolved" do
      create(:goal, organization: organization)

      result = tool.execute(owner: "nobody-like-this")

      expect(result).to eq([])
    end
  end

  describe "initiative counts" do
    it "reports total and unassigned (owner_id nil) initiative counts" do
      goal = create(:goal, organization: organization)
      create(:initiative, goal: goal, owner: create(:user, organization: organization))
      create(:initiative, goal: goal, owner: nil)
      create(:initiative, goal: goal, owner: nil)

      result = tool.execute

      summary = result.find { |g| g[:id] == goal.id }
      expect(summary[:initiatives]).to eq(total: 3, unassigned: 2)
    end
  end

  it "scopes to the given organization only" do
    other_org_goal = create(:goal)
    own_goal = create(:goal, organization: organization)

    result = tool.execute

    ids = result.map { |g| g[:id] }
    expect(ids).to include(own_goal.id)
    expect(ids).not_to include(other_org_goal.id)
  end

  it "filters by status and publishing_status" do
    draft = create(:goal, organization: organization, status: "not_started", publishing_status: "draft")
    create(:goal, organization: organization, status: "in_progress", publishing_status: "published")

    result = tool.execute(status: "not_started", publishing_status: "draft")

    expect(result.map { |g| g[:id] }).to contain_exactly(draft.id)
  end

  it "returns an error hash instead of raising on internal failure" do
    allow(organization).to receive(:goals).and_raise(StandardError, "boom")

    result = tool.execute

    expect(result).to eq(error: "Couldn't list goals: boom")
  end
end
