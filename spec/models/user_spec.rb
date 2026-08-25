require "rails_helper"

RSpec.describe User, type: :model do
  it { is_expected.to validate_presence_of(:email) }
  it { is_expected.to validate_presence_of(:provider_uid) }
  it { is_expected.to validate_presence_of(:full_name) }
  it { is_expected.to validate_presence_of(:time_zone) }
  it { is_expected.to belong_to(:organization) }

  it { is_expected.to have_many(:checkins).dependent(:destroy) }
  it { is_expected.to have_many(:goal_owners).dependent(:destroy) }
  it { is_expected.to have_many(:owned_goals).through(:goal_owners).source(:goal) }
  it { is_expected.to have_many(:created_goals).class_name("Goal").dependent(:nullify) }
  it { is_expected.to have_many(:created_initiatives).class_name("Initiative").dependent(:nullify) }
  it { is_expected.to have_many(:owned_initiatives).class_name("Initiative").dependent(:nullify) }
  it { is_expected.to have_many(:goal_updates).dependent(:nullify) }
  it { is_expected.to have_many(:metric_updates).dependent(:nullify) }
  it { is_expected.to have_many(:conversation_messages).dependent(:nullify) }
  it { is_expected.to have_many(:memories).dependent(:nullify) }
  it { is_expected.to have_many(:llm_calls).dependent(:nullify) }
  it { is_expected.to have_many(:owned_organizations).class_name("Organization").dependent(:nullify) }

  describe "#destroy" do
    it "destroys join/log rows that only mean something for this user" do
      user = create(:user)
      goal = create(:goal, organization: user.organization)
      goal.owners = [ user ]
      checkin = create(:checkin, organization: user.organization, user: user, goal: goal)

      user.destroy!

      expect(GoalOwner.exists?(goal: goal, user: user)).to eq(false)
      expect(Checkin.exists?(checkin.id)).to eq(false)
    end

    it "clears attribution on records that survive the user's deletion, without raising" do
      user = create(:user)
      org = user.organization
      org.update!(owner: user)
      goal = create(:goal, organization: org, creator: user)
      initiative = create(:initiative, goal: goal, creator: user, owner: user)
      goal_update = create(:goal_update, goal: goal, reported_by: user)
      metric_update = create(:metric_update, metric: create(:metric, goal: goal), reported_by: user)
      conversation = create(:conversation, organization: org)
      message = create(:conversation_message, conversation: conversation, user: user)
      memory = create(:memory, organization: org, user: user)
      llm_call = create(:llm_call, organization: org, user: user)

      expect { user.destroy! }.not_to raise_error

      expect(org.reload.owner_id).to be_nil
      expect(goal.reload.creator_id).to be_nil
      expect(initiative.reload.creator_id).to be_nil
      expect(initiative.reload.owner_id).to be_nil
      expect(goal_update.reload.reported_by_id).to be_nil
      expect(metric_update.reload.reported_by_id).to be_nil
      expect(message.reload.user_id).to be_nil
      expect(memory.reload.user_id).to be_nil
      expect(llm_call.reload.user_id).to be_nil
    end
  end

  describe ".create_from_slack" do
    let(:organization) { create(:organization) }

    it "creates a user from a Slack::Type::User" do
      user = User.create_from_slack(slack_user_response.user, organization.id, :owner)

      expect(user).to be_persisted
      expect(user.provider_uid).to eq("U00000000")
      expect(user.email).to eq("owner@example.com")
      expect(user.role).to eq("owner")
      expect(user.images["image_192"]).to be_present
    end

    it "defaults role to member" do
      user = User.create_from_slack(slack_user_response.user, organization.id)
      expect(user.role).to eq("member")
    end
  end

  describe "#admin_or_owner?" do
    it { expect(build(:user, role: :owner).admin_or_owner?).to be(true) }
    it { expect(build(:user, role: :admin).admin_or_owner?).to be(true) }
    it { expect(build(:user, role: :member).admin_or_owner?).to be(false) }
  end
end
