require "rails_helper"

RSpec.describe GoalLifecycle do
  describe ".status_for" do
    it "is not_started when start_date is blank" do
      expect(described_class.status_for(nil)).to eq(:not_started)
    end

    it "is not_started when start_date is in the future" do
      expect(described_class.status_for(1.day.from_now.to_date)).to eq(:not_started)
    end

    it "is in_progress once start_date has arrived" do
      expect(described_class.status_for(Date.current)).to eq(:in_progress)
      expect(described_class.status_for(1.day.ago.to_date)).to eq(:in_progress)
    end
  end

  describe ".outcome_for" do
    let(:goal) { create(:goal) }

    it "is completed when an increase-direction metric reached its target" do
      create(:metric, goal: goal, direction: "increase", start_value: 0, current_value: 40, target_value: 40)

      expect(described_class.outcome_for(goal)).to eq(:completed)
    end

    it "is completed when an increase-direction metric exceeded its target" do
      create(:metric, goal: goal, direction: "increase", start_value: 0, current_value: 55, target_value: 40)

      expect(described_class.outcome_for(goal)).to eq(:completed)
    end

    it "is ended when an increase-direction metric fell short of its target" do
      create(:metric, goal: goal, direction: "increase", start_value: 0, current_value: 30, target_value: 40)

      expect(described_class.outcome_for(goal)).to eq(:ended)
    end

    it "is completed when a decrease-direction metric reached (or went below) its target" do
      create(:metric, goal: goal, direction: "decrease", start_value: 100, current_value: 5, target_value: 5)

      expect(described_class.outcome_for(goal)).to eq(:completed)
    end

    it "is ended when a decrease-direction metric is still above its target" do
      create(:metric, goal: goal, direction: "decrease", start_value: 100, current_value: 20, target_value: 5)

      expect(described_class.outcome_for(goal)).to eq(:ended)
    end

    it "is ended when the goal has no metric" do
      expect(described_class.outcome_for(goal)).to eq(:ended)
    end
  end
end
