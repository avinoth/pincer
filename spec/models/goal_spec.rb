require "rails_helper"

RSpec.describe Goal do
  it "owns users through the goal_owners join table" do
    goal = create(:goal)
    u1 = create(:user, organization: goal.organization)
    u2 = create(:user, organization: goal.organization)

    goal.owners = [ u1, u2 ]

    expect(goal.reload.owners).to contain_exactly(u1, u2)
    expect(goal.goal_owners.count).to eq(2)
  end

  it "supports a parent / sub-goal self reference" do
    parent = create(:goal)
    child = create(:goal, organization: parent.organization, parent: parent)

    expect(child.parent).to eq(parent)
    expect(parent.sub_goals).to include(child)
  end

  it "keeps the creator distinct from owners" do
    goal = create(:goal)
    owner = create(:user, organization: goal.organization)
    goal.owners = [ owner ]

    expect(goal.creator).not_to eq(owner)
    expect(goal.owners).not_to include(goal.creator)
  end

  it "requires a title" do
    goal = build(:goal, title: nil)
    expect(goal).not_to be_valid
    expect(goal.errors[:title]).to be_present
  end

  it "requires start and end dates" do
    goal = build(:goal, start_date: nil, end_date: nil)
    expect(goal).not_to be_valid
    expect(goal.errors[:start_date]).to be_present
    expect(goal.errors[:end_date]).to be_present
  end

  it "rejects an end date before the start date" do
    goal = build(:goal, start_date: "2026-09-01", end_date: "2026-08-01")
    expect(goal).not_to be_valid
    expect(goal.errors[:end_date]).to include("can't be before the start date")
  end

  it "allows an end date equal to the start date" do
    goal = create(:goal, start_date: "2026-08-01", end_date: "2026-08-01")
    expect(goal).to be_valid
  end

  it "allows an end date after the start date" do
    goal = create(:goal, start_date: "2026-08-01", end_date: "2026-09-01")
    expect(goal).to be_valid
  end

  it "requires at least one owner" do
    goal = build(:goal)
    goal.owners = []
    expect(goal).not_to be_valid
    expect(goal.errors[:owners]).to be_present
  end

  it "exposes prefixed status and health enums" do
    goal = create(:goal)
    expect(goal).to be_status_in_progress

    goal.health_at_risk!
    expect(goal).to be_health_at_risk
  end

  it "exposes a prefixed publishing_status enum, defaulting to published" do
    goal = create(:goal)
    expect(goal).to be_publishing_published

    draft = create(:goal, publishing_status: "draft")
    expect(draft).to be_publishing_draft
  end

  it "rejects moving a published goal back to draft" do
    goal = create(:goal, publishing_status: "published")

    goal.publishing_status = "draft"

    expect(goal).not_to be_valid
    expect(goal.errors[:publishing_status]).to be_present
  end

  it "allows a draft goal to be published" do
    goal = create(:goal, publishing_status: "draft")

    goal.publishing_status = "published"

    expect(goal).to be_valid
  end

  describe "#modifiable_by?" do
    it "is true for the creator's Slack user id" do
      goal = create(:goal)

      expect(goal.modifiable_by?(goal.creator.provider_uid)).to eq(true)
    end

    it "is true for an owner's Slack user id" do
      goal = create(:goal)
      owner = create(:user, organization: goal.organization)
      goal.owners = [ owner ]

      expect(goal.modifiable_by?(owner.provider_uid)).to eq(true)
    end

    it "is false for an unrelated Slack user id" do
      goal = create(:goal)

      expect(goal.modifiable_by?("U_UNRELATED")).to eq(false)
    end

    it "is false for a blank Slack user id" do
      goal = create(:goal)

      expect(goal.modifiable_by?(nil)).to eq(false)
      expect(goal.modifiable_by?("")).to eq(false)
    end
  end

  describe "#accepts_initiatives?" do
    it "is true for a goal in a non-terminal status" do
      %w[not_started in_progress].each do |status|
        goal = create(:goal, status: status)
        expect(goal.accepts_initiatives?).to eq(true)
      end
    end

    it "is false for a goal in a terminal status" do
      %w[completed ended].each do |status|
        goal = create(:goal, status: status)
        expect(goal.accepts_initiatives?).to eq(false)
      end
    end
  end

  describe ".accepting_initiatives" do
    it "excludes goals in a terminal status" do
      open_goal = create(:goal, status: "in_progress")
      create(:goal, status: "completed")
      create(:goal, status: "ended")

      expect(Goal.accepting_initiatives).to contain_exactly(open_goal)
    end
  end

  describe GoalOwner do
    it "enforces one owner row per user per goal" do
      goal = create(:goal)
      user = create(:user, organization: goal.organization)
      goal.owners << user

      duplicate = GoalOwner.new(goal: goal, user: user)
      expect(duplicate).not_to be_valid
    end
  end
end
