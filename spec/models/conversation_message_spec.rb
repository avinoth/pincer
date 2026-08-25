require "rails_helper"

RSpec.describe ConversationMessage do
  it { is_expected.to belong_to(:conversation) }
  it { is_expected.to belong_to(:user).optional }

  it { is_expected.to validate_presence_of(:role) }

  it do
    is_expected.to define_enum_for(:role)
      .with_values(user: "user", assistant: "assistant", tool: "tool", event: "event")
      .backed_by_column_of_type(:string)
      .with_prefix
  end

  it "can be created without a user (e.g. assistant or tool messages)" do
    message = create(:conversation_message, role: "assistant", user: nil)
    expect(message).to be_valid
  end

  it "stores tool call payloads as jsonb" do
    message = create(:conversation_message,
      role: "assistant",
      tool_calls: [ { "id" => "call_1", "name" => "create_goal" } ])

    expect(message.reload.tool_calls).to eq([ { "id" => "call_1", "name" => "create_goal" } ])
  end
end
