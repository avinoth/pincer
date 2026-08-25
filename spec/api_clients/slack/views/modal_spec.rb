require "rails_helper"

RSpec.describe Slack::Views::ExampleModal do
  it "builds a valid modal view" do
    view = described_class.new.to_h

    expect(view[:type]).to eq("modal")
    expect(view[:callback_id]).to eq("example")
    expect(view[:title]).to eq(type: "plain_text", text: "Example", emoji: true)
    expect(view[:submit]).to eq(type: "plain_text", text: "Submit", emoji: true)
    expect(view[:blocks]).to be_present

    input = view[:blocks].find { |b| b[:type] == "input" }
    expect(input[:element][:type]).to eq("plain_text_input")
  end
end
