require "rails_helper"

RSpec.describe Slack::Blocks do
  it "builds a header with a plain_text object" do
    expect(described_class.header("Hi")).to eq(
      type: "header", text: { type: "plain_text", text: "Hi", emoji: true },
    )
  end

  it "renders a String section as mrkdwn" do
    expect(described_class.section("*bold*")).to eq(
      type: "section", text: { type: "mrkdwn", text: "*bold*" },
    )
  end

  it "builds a button and omits nil keys" do
    btn = described_class.button("Go", action_id: "go")
    expect(btn).to eq(type: "button", text: { type: "plain_text", text: "Go", emoji: true }, action_id: "go")
    expect(btn).not_to have_key(:value)
    expect(btn).not_to have_key(:style)
  end

  it "wraps elements in an actions block" do
    btn = described_class.button("Go", action_id: "go")
    expect(described_class.actions([ btn ])).to eq(type: "actions", elements: [ btn ])
  end

  it "builds an input wrapping an element" do
    element = described_class.plain_text_input(action_id: "note", multiline: true)
    input = described_class.input(label: "Note", element: element, block_id: "b")
    expect(input[:type]).to eq("input")
    expect(input[:label]).to eq(type: "plain_text", text: "Note", emoji: true)
    expect(input[:element]).to eq(element)
  end

  it "builds checkboxes and omits initial_options when none are given" do
    opt = described_class.option("Save as draft", "draft")
    checkboxes = described_class.checkboxes(action_id: "draft", options: [ opt ])

    expect(checkboxes).to eq(type: "checkboxes", action_id: "draft", options: [ opt ])
    expect(checkboxes).not_to have_key(:initial_options)
  end

  it "builds checkboxes with initial_options when given" do
    opt = described_class.option("Save as draft", "draft")
    checkboxes = described_class.checkboxes(action_id: "draft", options: [ opt ], initial_options: [ opt ])

    expect(checkboxes[:initial_options]).to eq([ opt ])
  end

  it "builds an image element (the context-block form, distinct from the image block)" do
    element = described_class.image_element(image_url: "https://example.com/a.png", alt_text: "Ada")

    expect(element).to eq(type: "image", image_url: "https://example.com/a.png", alt_text: "Ada")
  end
end
