require "rails_helper"

RSpec.describe Slack::Messages::GoalDisplay do
  let(:organization) { create(:organization) }
  let(:owner) { create(:user, organization: organization, provider_uid: "U_OWNER", full_name: "Ada Lovelace", images: {}) }

  def card_blocks(payload)
    payload[:attachments].sole[:blocks]
  end

  def buttons(payload)
    card_blocks(payload).flat_map { |b| Array(b[:elements]) }.select { |e| e[:type] == "button" }
  end

  describe "a draft goal" do
    let(:goal) do
      create(:goal, organization: organization, title: "Grow activation", description: "Ship the funnel work",
        publishing_status: "draft", owners: [ owner ], update_channel: "C_UPDATES",
        summary_day: 2, summary_time: "17:00", start_date: "2026-08-01", end_date: "2026-09-15")
    end

    it "wraps a single colored attachment around the blocks" do
      payload = described_class.new(goal: goal).to_h

      expect(payload).not_to have_key(:blocks)
      expect(payload[:attachments]).to be_an(Array)
      expect(payload[:attachments].size).to eq(1)
      expect(payload[:attachments].first[:color]).to eq(Slack::GoalCardPresenter.new(goal: goal).card_color)
    end

    it "shows a Draft badge, detailed fields, and Publish + Edit buttons" do
      payload = described_class.new(goal: goal).to_h

      expect(payload[:text]).to eq("Draft: Grow activation")
      expect(card_blocks(payload).to_s).to include("Grow activation")
      expect(card_blocks(payload).to_s).to include("📝 Draft")
      expect(card_blocks(payload).to_s).to include("Ship the funnel work")
      expect(card_blocks(payload).to_s).to include("👤 Ada Lovelace")
      expect(card_blocks(payload).to_s).to include("Aug 1")
      expect(card_blocks(payload).to_s).to include("Sep 15, 2026")
      expect(card_blocks(payload).to_s).to include("<#C_UPDATES>")
      expect(card_blocks(payload).to_s).to include("Tuesday 17:00")

      goal_buttons = buttons(payload)
      expect(goal_buttons.map { |b| b[:action_id] }).to eq([ "publish_goal", "edit_goal" ])
      expect(goal_buttons.map { |b| b[:value] }.uniq).to eq([ goal.id.to_s ])
      expect(goal_buttons.find { |b| b[:action_id] == "publish_goal" }[:style]).to eq("primary")
    end

    it "renders an owner's avatar as an image element when they have one" do
      owner.update!(images: { "image_72" => "https://x/a.png" })

      payload = described_class.new(goal: goal).to_h

      images = card_blocks(payload).flat_map { |b| Array(b[:elements]) }.select { |e| e[:type] == "image" }
      expect(images).to include(type: "image", image_url: "https://x/a.png", alt_text: "Ada Lovelace")
    end

    it "includes a Parent field when the goal has a parent" do
      parent = create(:goal, organization: organization, title: "North Star")
      goal.update!(parent: parent)

      payload = described_class.new(goal: goal).to_h

      expect(card_blocks(payload).to_s).to include("Parent")
      expect(card_blocks(payload).to_s).to include("North Star")
    end

    it "omits the description section when there is none" do
      goal.update!(description: nil)

      payload = described_class.new(goal: goal).to_h

      section_texts = card_blocks(payload).select { |b| b[:type] == "section" }.map { |b| b.dig(:text, :text) }
      expect(section_texts).not_to include("Ship the funnel work")
    end
  end

  describe "the Metric field" do
    let(:goal) { create(:goal, organization: organization, owners: [ owner ]) }

    it "renders name, current -> target, unit, and an up arrow for an increase metric" do
      create(:metric, goal: goal, name: "MRR", direction: "increase",
        start_value: 20, current_value: 20, target_value: 40, unit: "%")

      payload = described_class.new(goal: goal).to_h

      expect(card_blocks(payload).to_s).to include("MRR: 20% → 40% ↗︎")
    end

    it "renders a down arrow for a decrease metric and trims a whole-number value's trailing .0" do
      create(:metric, goal: goal, name: "Churn", direction: "decrease",
        start_value: 8, current_value: 8.5, target_value: 5, unit: "%")

      payload = described_class.new(goal: goal).to_h

      expect(card_blocks(payload).to_s).to include("Churn: 8.5% → 5% ↘︎")
    end

    it "omits the field when the goal has no metric" do
      payload = described_class.new(goal: goal).to_h

      expect(card_blocks(payload).to_s).not_to include("Metric")
    end

    it "renders a progress bar and remaining-to-target delta when the metric has measurable progress" do
      create(:metric, goal: goal, name: "MRR", direction: "increase",
        start_value: 0, current_value: 29, target_value: 100, unit: "$")

      payload = described_class.new(goal: goal).to_h

      expect(card_blocks(payload).to_s).to include("▓▓▓░░░░░░░ 29%")
      expect(card_blocks(payload).to_s).to include("$71 to go")
    end

    it "omits the remaining-to-target line once the target is reached" do
      create(:metric, goal: goal, name: "MRR", direction: "increase",
        start_value: 0, current_value: 100, target_value: 100, unit: "$")

      payload = described_class.new(goal: goal).to_h

      expect(card_blocks(payload).to_s).not_to include("to go")
    end
  end

  describe "pace and days left" do
    let(:goal) do
      create(:goal, organization: organization, owners: [ owner ],
        start_date: 10.days.ago.to_date, end_date: 10.days.from_now.to_date)
    end

    it "renders a pace verdict alongside days left when there's a metric with progress" do
      create(:metric, goal: goal, direction: "increase", start_value: 0, current_value: 9, target_value: 10)

      payload = described_class.new(goal: goal).to_h

      expect(card_blocks(payload).to_s).to include("🔥 ahead of pace")
      expect(card_blocks(payload).to_s).to include("10 days left")
    end

    it "renders only days left when there's no metric" do
      payload = described_class.new(goal: goal).to_h

      expect(card_blocks(payload).to_s).not_to include("pace")
      expect(card_blocks(payload).to_s).to include("10 days left")
    end
  end

  describe "initiatives" do
    let(:goal) { create(:goal, organization: organization, owners: [ owner ]) }

    it "lists each initiative with a status emoji and owner (or unassigned)" do
      assigned_owner = create(:user, organization: organization, full_name: "Grace Hopper")
      create(:initiative, goal: goal, title: "Ship onboarding revamp", status: "in_progress", owner: assigned_owner)
      create(:initiative, goal: goal, title: "Audit funnel drop-off", status: "proposed", owner: nil)

      payload = described_class.new(goal: goal).to_h

      text = card_blocks(payload).to_s
      expect(text).to include("🚧 Ship onboarding revamp")
      expect(text).to include("Grace Hopper")
      expect(text).to include("📋 Audit funnel drop-off")
      expect(text).to include("unassigned")
    end

    it "omits the Initiatives section when there are none" do
      payload = described_class.new(goal: goal).to_h

      expect(card_blocks(payload).to_s).not_to include("Initiatives")
    end
  end

  describe "a published goal" do
    let(:goal) do
      create(:goal, organization: organization, title: "Grow activation", status: "in_progress",
        publishing_status: "published", owners: [ owner ])
    end

    it "shows the lifecycle badge and only an Edit button" do
      payload = described_class.new(goal: goal).to_h

      expect(payload[:text]).to eq("In progress: Grow activation")
      expect(card_blocks(payload).to_s).to include("🟢 In progress")

      goal_buttons = buttons(payload)
      expect(goal_buttons.map { |b| b[:action_id] }).to eq([ "edit_goal" ])
      expect(goal_buttons.first[:value]).to eq(goal.id.to_s)
    end

    %w[not_started in_progress completed ended].each do |status|
      it "renders the #{status} lifecycle badge" do
        goal.update!(status: status)

        payload = described_class.new(goal: goal).to_h

        expect(card_blocks(payload).to_s).to include(Slack::Messages::GoalDisplay::LIFECYCLE_BADGES.fetch(status))
      end
    end

    it "renders a health badge alongside the lifecycle badge when health is set" do
      goal.update!(health: "at_risk")

      payload = described_class.new(goal: goal).to_h

      expect(card_blocks(payload).to_s).to include("🟡 At risk")
    end

    it "omits the Updates field when no notification channel is set" do
      goal.update!(update_channel: nil)

      payload = described_class.new(goal: goal).to_h

      expect(card_blocks(payload).to_s).not_to include("Updates")
    end
  end
end
