require "rails_helper"

RSpec.describe Organization, type: :model do
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:provider) }
  it { is_expected.to validate_presence_of(:status) }
  it { is_expected.to validate_presence_of(:time_zone) }

  it { is_expected.to have_one(:slack_workspace).dependent(:destroy) }
  it { is_expected.to have_many(:users).dependent(:destroy) }
  it { is_expected.to have_many(:goals).dependent(:destroy) }
  it { is_expected.to have_many(:conversations).dependent(:destroy) }
  it { is_expected.to have_many(:memories).dependent(:destroy) }
  it { is_expected.to have_many(:llm_calls).dependent(:nullify) }
  it { is_expected.to have_many(:slack_interactions).dependent(:nullify) }
  it { is_expected.to belong_to(:owner).class_name("User").optional }

  describe "#destroy" do
    it "cascades cleanly across the full graph — goals, initiatives, users, checkins, " \
       "conversations, and every user/org-attributed record" do
      organization = create(:organization)
      creator = create(:user, organization: organization)
      owner = create(:user, organization: organization)
      organization.update!(owner: creator)

      goal = create(:goal, organization: organization, creator: creator)
      goal.owners = [ owner ]
      metric = create(:metric, goal: goal)
      create(:metric_update, metric: metric, reported_by: owner)
      initiative = create(:initiative, goal: goal, creator: creator, owner: owner)
      checkin = create(:checkin, organization: organization, user: owner, goal: goal, initiative: initiative)
      create(:goal_update, goal: goal, initiative: initiative, checkin: checkin, reported_by: owner)

      conversation = create(:conversation, organization: organization)
      create(:conversation_message, conversation: conversation, user: owner)
      agent_run = create(:agent_run, conversation: conversation)
      create(:llm_call, organization: organization, user: owner, agent_run: agent_run)

      create(:memory, organization: organization, user: owner)
      create(:slack_interaction, organization: organization)

      expect { organization.destroy! }.not_to raise_error
      expect(Organization.exists?(organization.id)).to eq(false)
      expect(Goal.exists?(goal.id)).to eq(false)
      expect(User.exists?(owner.id)).to eq(false)
    end
  end

  describe ".create_from_slack" do
    it "creates the organization and its slack_workspace from the auth response" do
      organization = Organization.create_from_slack(slack_auth_response)

      expect(organization).to be_persisted
      expect(organization).to be_active
      expect(organization.provider).to eq("slack")
      expect(organization.slack_workspace.identifier).to eq("T00000000")
      expect(organization.slack_workspace.access_token).to be_present
      expect(organization.slack_workspace.refresh_token).to be_present
    end
  end

  describe "#update_details_from_slack" do
    it "reactivates the org and refreshes workspace tokens" do
      organization = create(:organization, status: :inactive)
      create(:slack_workspace, organization: organization, access_token: "old")

      organization.update_details_from_slack(slack_auth_response)

      expect(organization.reload).to be_active
      expect(organization.slack_workspace.reload.access_token).not_to eq("old")
    end
  end
end
