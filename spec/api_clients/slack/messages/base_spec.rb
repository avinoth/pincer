require "rails_helper"

RSpec.describe Slack::Messages::Base do
  describe "#to_h" do
    it "renders top-level blocks when no color is set" do
      klass = Class.new(described_class) do
        def text = "hello"
        def blocks = [ section("hi") ]
      end

      payload = klass.new.to_h

      expect(payload).to eq(text: "hello", blocks: [ { type: "section", text: { type: "mrkdwn", text: "hi" } } ])
      expect(payload).not_to have_key(:attachments)
    end

    it "wraps blocks in a single colored attachment when color is set" do
      klass = Class.new(described_class) do
        def text = "hello"
        def blocks = [ section("hi") ]
        def color = "#2EB67D"
      end

      payload = klass.new.to_h

      expect(payload).to eq(
        text: "hello",
        attachments: [ { color: "#2EB67D", blocks: [ { type: "section", text: { type: "mrkdwn", text: "hi" } } ] } ]
      )
      expect(payload).not_to have_key(:blocks)
    end

    it "omits text when blank" do
      klass = Class.new(described_class) do
        def blocks = [ section("hi") ]
      end

      expect(klass.new.to_h).not_to have_key(:text)
    end
  end
end
