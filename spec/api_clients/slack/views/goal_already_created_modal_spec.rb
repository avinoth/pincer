require "rails_helper"

RSpec.describe Slack::Views::GoalAlreadyCreatedModal do
  it "shows the goal's title, creator, and date range, close-only" do
    creator = create(:user, full_name: "Jamie Rivera")
    goal = create(:goal, organization: creator.organization, creator: creator, title: "Grow activation",
      start_date: "2026-08-01", end_date: "2026-09-01")

    view = described_class.new(goal: goal).to_h

    expect(view[:type]).to eq("modal")
    expect(view[:title]).to eq(type: "plain_text", text: "Goal already created", emoji: true)
    expect(view[:close]).to eq(type: "plain_text", text: "Close", emoji: true)
    expect(view).not_to have_key(:submit)

    text = view[:blocks].sole[:text][:text]
    expect(text).to include("Grow activation")
    expect(text).to include("Jamie Rivera")
    expect(text).to include("Aug 1")
    expect(text).to include("Sep 1, 2026")
  end

  it "falls back to generic copy when the goal has been deleted" do
    view = described_class.new(goal: nil).to_h

    text = view[:blocks].sole[:text][:text]
    expect(text).to eq("This goal was already created.")
    expect(view).not_to have_key(:submit)
    expect(view[:close][:text]).to eq("Close")
  end
end
