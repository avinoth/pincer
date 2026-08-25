require "rails_helper"

RSpec.describe Slack::Messages::AssistantWelcome do
  it "builds a blocks payload greeting the user with the capability rundown and a CTA" do
    payload = described_class.new(name: "Ada").to_h

    expect(payload[:text]).to include("Ada")
    expect(payload[:blocks]).to be_present

    blocks_text = payload[:blocks].to_s
    expect(blocks_text).to include("Ada")
    expect(blocks_text).to include("Track goals & initiatives")
    expect(blocks_text).to include("Log progress")
    expect(blocks_text).to include("Stay in the loop")
    expect(blocks_text).to include("Remember what matters")
    expect(blocks_text).to include("pick a suggested prompt")
  end
end
