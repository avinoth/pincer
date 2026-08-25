require "rails_helper"

RSpec.describe SlackInteraction do
  it { is_expected.to belong_to(:organization).optional }
  it { is_expected.to validate_presence_of(:direction) }

  it do
    is_expected.to define_enum_for(:direction)
      .with_values(inbound: "inbound", outbound: "outbound")
      .backed_by_column_of_type(:string)
  end

  describe ".in_thread" do
    it "returns a channel thread's rows oldest-first, scoped to that thread" do
      first = create(:slack_interaction, channel_id: "C1", thread_ts: "10.0",
        created_at: 2.minutes.ago)
      second = create(:slack_interaction, channel_id: "C1", thread_ts: "10.0",
        created_at: 1.minute.ago)
      create(:slack_interaction, channel_id: "C1", thread_ts: "99.0") # other thread

      expect(described_class.in_thread("C1", "10.0")).to eq([ first, second ])
    end
  end
end
