require "rails_helper"

RSpec.describe Slack::GoalCardPresenter do
  let(:organization) { create(:organization) }

  describe "#card_color" do
    it "uses the grey not-started/ended base color when no health is set" do
      goal = create(:goal, organization: organization, status: "not_started", health: nil)
      expect(described_class.new(goal: goal).card_color).to eq("#9E9E9E")

      goal.update!(status: "ended")
      expect(described_class.new(goal: goal).card_color).to eq("#9E9E9E")
    end

    it "uses green for completed and blue for in_progress, with no health set" do
      goal = create(:goal, organization: organization, status: "completed", health: nil)
      expect(described_class.new(goal: goal).card_color).to eq("#2EB67D")

      goal.update!(status: "in_progress")
      expect(described_class.new(goal: goal).card_color).to eq("#3AA3E3")
    end

    it "lets health override the status-based color" do
      goal = create(:goal, organization: organization, status: "in_progress", health: "at_risk")
      expect(described_class.new(goal: goal).card_color).to eq("#E8A33D")

      goal.update!(health: "off_track")
      expect(described_class.new(goal: goal).card_color).to eq("#E01E5A")

      goal.update!(health: "on_track")
      expect(described_class.new(goal: goal).card_color).to eq("#2EB67D")
    end
  end

  describe "#progress_bar" do
    it "renders 10 unicode blocks proportional to progress_percent, plus the percent" do
      goal = create(:goal, organization: organization)
      create(:metric, goal: goal, direction: "increase", start_value: 0, current_value: 3, target_value: 10)

      expect(described_class.new(goal: goal).progress_bar).to eq("▓▓▓░░░░░░░ 30%")
    end

    it "is nil when the goal has no metric" do
      goal = create(:goal, organization: organization)
      expect(described_class.new(goal: goal).progress_bar).to be_nil
    end

    it "is nil when the metric has no measurable progress" do
      goal = create(:goal, organization: organization)
      create(:metric, goal: goal, start_value: 20, current_value: 25, target_value: 20)

      expect(described_class.new(goal: goal).progress_bar).to be_nil
    end
  end

  describe "#pace" do
    it "flags ahead of pace when progress is well beyond time elapsed" do
      goal = create(:goal, organization: organization, start_date: 10.days.ago.to_date, end_date: 10.days.from_now.to_date)
      create(:metric, goal: goal, direction: "increase", start_value: 0, current_value: 9, target_value: 10)

      pace = described_class.new(goal: goal).pace
      expect(pace).to eq(emoji: "🔥", label: "ahead of pace")
    end

    it "flags behind pace when progress lags well behind time elapsed" do
      goal = create(:goal, organization: organization, start_date: 10.days.ago.to_date, end_date: 10.days.from_now.to_date)
      create(:metric, goal: goal, direction: "increase", start_value: 0, current_value: 1, target_value: 10)

      pace = described_class.new(goal: goal).pace
      expect(pace).to eq(emoji: "⚠️", label: "behind pace")
    end

    it "flags on pace when progress roughly tracks time elapsed" do
      goal = create(:goal, organization: organization, start_date: 10.days.ago.to_date, end_date: 10.days.from_now.to_date)
      create(:metric, goal: goal, direction: "increase", start_value: 0, current_value: 5, target_value: 10)

      pace = described_class.new(goal: goal).pace
      expect(pace).to eq(emoji: "✅", label: "on pace")
    end

    it "is nil when the goal has no metric" do
      goal = create(:goal, organization: organization, start_date: 10.days.ago.to_date, end_date: 10.days.from_now.to_date)
      expect(described_class.new(goal: goal).pace).to be_nil
    end

    it "is nil when the goal has no start_date/end_date" do
      goal = create(:goal, organization: organization)
      create(:metric, goal: goal, direction: "increase", start_value: 0, current_value: 5, target_value: 10)
      goal.assign_attributes(start_date: nil, end_date: nil)

      expect(described_class.new(goal: goal).pace).to be_nil
    end
  end

  describe "#days_left" do
    it "counts the days from today to end_date" do
      goal = create(:goal, organization: organization, end_date: 5.days.from_now.to_date)
      expect(described_class.new(goal: goal).days_left).to eq(5)
    end

    it "is nil without an end_date" do
      goal = create(:goal, organization: organization)
      goal.assign_attributes(end_date: nil)

      expect(described_class.new(goal: goal).days_left).to be_nil
    end
  end

  describe "#owners_avatars" do
    it "renders an image element for an owner with an avatar" do
      owner = create(:user, organization: organization, full_name: "Ada Lovelace", images: { "image_72" => "https://x/a.png" })
      goal = create(:goal, organization: organization, owners: [ owner ])

      elements = described_class.new(goal: goal).owners_avatars
      expect(elements).to eq([ { type: "image", image_url: "https://x/a.png", alt_text: "Ada Lovelace" } ])
    end

    it "falls back to a 👤 name text element when there's no avatar" do
      owner = create(:user, organization: organization, full_name: "Ada Lovelace", images: {})
      goal = create(:goal, organization: organization, owners: [ owner ])

      elements = described_class.new(goal: goal).owners_avatars
      expect(elements).to eq([ { type: "mrkdwn", text: "👤 Ada Lovelace" } ])
    end
  end

  describe "#last_updated_text" do
    it "is nil with no metric_updates" do
      goal = create(:goal, organization: organization)
      create(:metric, goal: goal)

      expect(described_class.new(goal: goal).last_updated_text).to be_nil
    end

    it "reports days since the most recent metric_update" do
      goal = create(:goal, organization: organization)
      metric = create(:metric, goal: goal)
      user = create(:user, organization: organization)
      metric.metric_updates.create!(reported_by: user, value: 5, created_at: 3.days.ago)

      expect(described_class.new(goal: goal).last_updated_text).to eq("Updated 3d ago")
    end

    it "says 'Updated today' when updated within the last day" do
      goal = create(:goal, organization: organization)
      metric = create(:metric, goal: goal)
      user = create(:user, organization: organization)
      metric.metric_updates.create!(reported_by: user, value: 5, created_at: 1.hour.ago)

      expect(described_class.new(goal: goal).last_updated_text).to eq("Updated today")
    end
  end
end
