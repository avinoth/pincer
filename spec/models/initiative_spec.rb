require "rails_helper"

RSpec.describe Initiative do
  it { is_expected.to belong_to(:goal) }
  it { is_expected.to belong_to(:owner).class_name("User").optional }
  it { is_expected.to belong_to(:creator).class_name("User").optional }

  it { is_expected.to validate_presence_of(:title) }
  it { is_expected.to validate_presence_of(:status) }

  it do
    is_expected.to define_enum_for(:status)
      .with_values(
        proposed: "proposed",
        in_progress: "in_progress",
        done: "done",
        dropped: "dropped")
      .backed_by_column_of_type(:string)
      .with_prefix("status")
  end

  it "defaults to proposed" do
    initiative = create(:initiative)
    expect(initiative).to be_status_proposed
  end

  it "is readable through the parent goal" do
    goal = create(:goal)
    initiative = create(:initiative, goal: goal)

    expect(goal.initiatives).to contain_exactly(initiative)
  end

  it "survives its creator being deleted, with creator nullified" do
    creator = create(:user)
    initiative = create(:initiative, creator: creator)

    creator.destroy!

    expect(initiative.reload.creator_id).to be_nil
  end

  describe "#modifiable_by?" do
    it "is true for the initiative's own owner" do
      owner = create(:user, provider_uid: "U_OWNER")
      initiative = create(:initiative, owner: owner)

      expect(initiative.modifiable_by?("U_OWNER")).to eq(true)
    end

    it "is true for the parent goal's creator" do
      goal = create(:goal)
      initiative = create(:initiative, goal: goal)

      expect(initiative.modifiable_by?(goal.creator.provider_uid)).to eq(true)
    end

    it "is true for one of the parent goal's owners" do
      goal = create(:goal)
      goal_owner = create(:user, organization: goal.organization)
      goal.owners = [ goal_owner ]
      initiative = create(:initiative, goal: goal)

      expect(initiative.modifiable_by?(goal_owner.provider_uid)).to eq(true)
    end

    it "is false for an unrelated Slack user id" do
      initiative = create(:initiative)

      expect(initiative.modifiable_by?("U_UNRELATED")).to eq(false)
    end

    it "is false for a blank Slack user id" do
      initiative = create(:initiative)

      expect(initiative.modifiable_by?(nil)).to eq(false)
      expect(initiative.modifiable_by?("")).to eq(false)
    end
  end
end
