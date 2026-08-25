require "rails_helper"

RSpec.describe SendCheckinNudgeJob do
  let(:organization) { create(:organization) }
  let!(:workspace) { create(:slack_workspace, organization: organization) }
  let(:owner) { create(:user, organization: organization, provider_uid: "U_OWNER") }
  let(:goal) { create(:goal, organization: organization, owners: [ owner ], title: "Grow activation") }
  let!(:metric) { create(:metric, goal: goal) }
  let!(:checkin) do
    create(:checkin, organization: organization, user: owner, goal: goal, status: "pending", period_key: "2026-08-20")
  end

  let(:slack_response) { { ok: true, ts: "1700000000.000123", channel: "D0123" }.with_indifferent_access }
  let(:sender) { instance_double(Slack::Request::SendMessage, send_message: slack_response) }

  before do
    allow(Slack::Request::SendMessage).to receive(:new).with(workspace).and_return(sender)
  end

  def perform(checkin_ids: [ checkin.id ])
    described_class.perform_now(user_id: owner.id, checkin_ids: checkin_ids)
  end

  it "DMs the owner a CheckinNudge card via the Slack client" do
    perform

    expect(sender).to have_received(:send_message) do |recipient, payload|
      expect(recipient).to eq("U_OWNER")
      expect(payload[:blocks].to_s).to include("Grow activation")
    end
  end

  it "stamps the returned channel/ts onto the checkins and flips them notified" do
    perform

    checkin.reload
    expect(checkin.slack_channel_id).to eq("D0123")
    expect(checkin.slack_thread_ts).to eq("1700000000.000123")
    expect(checkin).to be_status_notified
    expect(checkin.notified_at).to be_present
  end

  it "pre-creates a dm Conversation naming the goal in its context_hint" do
    perform

    conversation = organization.conversations.sole
    expect(conversation.surface).to eq("dm")
    expect(conversation.slack_channel_id).to eq("D0123")
    expect(conversation.slack_thread_ts).to eq("1700000000.000123")
    expect(conversation.context_hint).to include("Grow activation")
  end

  it "clubs multiple checkins for the same owner under one Conversation/thread" do
    initiative = create(:initiative, goal: goal, owner: owner)
    other_checkin = create(:checkin, organization: organization, user: owner, goal: goal, initiative: initiative,
                           status: "pending", period_key: "2026-08-20")

    perform(checkin_ids: [ checkin.id, other_checkin.id ])

    expect(organization.conversations.count).to eq(1)
    expect(checkin.reload.slack_thread_ts).to eq("1700000000.000123")
    expect(other_checkin.reload.slack_thread_ts).to eq("1700000000.000123")
  end

  it "no-ops for an unknown user" do
    described_class.perform_now(user_id: -1, checkin_ids: [ checkin.id ])

    expect(sender).not_to have_received(:send_message)
  end

  it "no-ops when none of the given checkins are still pending for this user" do
    checkin.update!(status: "notified")

    perform

    expect(sender).not_to have_received(:send_message)
  end

  it "no-ops when the organization has no Slack workspace" do
    lone_org = create(:organization)
    lone_owner = create(:user, organization: lone_org)
    lone_goal = create(:goal, organization: lone_org, owners: [ lone_owner ])
    create(:metric, goal: lone_goal)
    lone_checkin = create(:checkin, organization: lone_org, user: lone_owner, goal: lone_goal, period_key: "2026-08-20")

    expect {
      described_class.perform_now(user_id: lone_owner.id, checkin_ids: [ lone_checkin.id ])
    }.not_to raise_error
    expect(sender).not_to have_received(:send_message)
  end

  it "rescues (never raises) when the Slack call fails" do
    allow(sender).to receive(:send_message).and_raise(StandardError, "slack is down")

    expect { perform }.not_to raise_error

    expect(checkin.reload).to be_status_pending
  end

  describe "concurrency configuration" do
    it "serializes sends per owner" do
      config = described_class.good_job_concurrency_config
      expect(config[:perform_limit]).to eq(1)

      job = described_class.new(user_id: 42, checkin_ids: [ 1 ])
      expect(job.good_job_concurrency_key).to eq("send-checkin-nudge:42")
    end
  end
end
