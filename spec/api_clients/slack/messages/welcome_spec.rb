require "rails_helper"

RSpec.describe Slack::Messages::Welcome do
  it "builds a blocks payload with a text fallback" do
    organization = build(:organization, name: "Acme")
    owner = build(:user, full_name: "Ada Lovelace")

    payload = described_class.new(organization: organization, owner: owner).to_h

    expect(payload[:text]).to include("Ada Lovelace").and include("Acme")
    expect(payload[:blocks].first[:type]).to eq("header")
    expect(payload[:blocks].to_s).to include("Acme")
  end

  it "includes the capability rundown and a suggested-prompt CTA" do
    organization = build(:organization, name: "Acme")
    owner = build(:user, full_name: "Ada Lovelace")

    blocks_text = described_class.new(organization: organization, owner: owner).blocks.to_s

    expect(blocks_text).to include("Track goals & initiatives")
    expect(blocks_text).to include("Log progress")
    expect(blocks_text).to include("Stay in the loop")
    expect(blocks_text).to include("Remember what matters")
    expect(blocks_text).to include("Create a goal for the upcoming quarter")
  end
end
