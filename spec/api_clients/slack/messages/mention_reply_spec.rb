require "rails_helper"

RSpec.describe Slack::Messages::MentionReply do
  it "echoes the text (stripping the bot mention) with a fallback and a wave button" do
    payload = described_class.new(text: "<@U0BOT> hello there").to_h

    expect(payload[:text]).to eq("You said: hello there")
    expect(payload[:blocks]).to be_present
    expect(payload[:blocks].to_s).to include("hello there")

    action_ids = payload[:blocks].flat_map { |b| Array(b[:elements]) }.filter_map { |e| e[:action_id] }
    expect(action_ids).to include("wave")
  end

  it "handles an empty (mention-only) message" do
    payload = described_class.new(text: "<@U0BOT>").to_h
    expect(payload[:blocks].to_s).to include("nothing")
  end
end
