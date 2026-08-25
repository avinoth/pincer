require "rails_helper"

RSpec.describe Metric do
  describe "validations" do
    it "requires name, target_value, and direction" do
      metric = Metric.new
      expect(metric).not_to be_valid
      expect(metric.errors.attribute_names).to include(:name, :target_value, :direction)
    end
  end

  describe "one metric per goal" do
    it "rejects a second metric on the same goal at the database level" do
      goal = create(:goal)
      create(:metric, goal: goal)
      expect { create(:metric, goal: goal) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  it "has many metric_updates and reads them back" do
    metric = create(:metric)
    user = create(:user, organization: metric.goal.organization)
    metric.metric_updates.create!(reported_by: user, value: 25)

    expect(metric.reload.metric_updates.count).to eq(1)
  end

  describe ".format_value" do
    it "prefixes currency symbols with no space" do
      expect(described_class.format_value(40, "$")).to eq("$40")
      expect(described_class.format_value(40, "£")).to eq("£40")
      expect(described_class.format_value(40, "€")).to eq("€40")
    end

    it "suffixes a symbolic unit with no space" do
      expect(described_class.format_value(40, "%")).to eq("40%")
    end

    it "suffixes a word unit with a space" do
      expect(described_class.format_value(40, "signups")).to eq("40 signups")
    end

    it "renders a bare number when the unit is blank" do
      expect(described_class.format_value(40, nil)).to eq("40")
      expect(described_class.format_value(40, "")).to eq("40")
    end

    it "renders a bare em-dash placeholder when the value is nil, ignoring the unit" do
      expect(described_class.format_value(nil, nil)).to eq("—")
      # A unit on its own ("—%", "$—") is meaningless with no value, so it's dropped.
      expect(described_class.format_value(nil, "%")).to eq("—")
      expect(described_class.format_value(nil, "$")).to eq("—")
    end

    it "trims a whole-number value's trailing .0 but keeps other decimals" do
      expect(described_class.format_value(20.0, "%")).to eq("20%")
      expect(described_class.format_value(5.5, "%")).to eq("5.5%")
    end
  end

  describe ".format_number" do
    it "trims a whole-number decimal's trailing .0" do
      expect(described_class.format_number(20.0)).to eq("20")
    end

    it "keeps a fractional decimal as-is" do
      expect(described_class.format_number(5.5)).to eq("5.5")
    end

    it "returns nil (not the em-dash) for a blank value" do
      expect(described_class.format_number(nil)).to be_nil
      expect(described_class.format_number("")).to be_nil
    end
  end

  describe "#formatted_current_value / #formatted_target_value" do
    it "formats the metric's own values using its unit" do
      metric = build(:metric, current_value: 20, target_value: 40, unit: "$")
      expect(metric.formatted_current_value).to eq("$20")
      expect(metric.formatted_target_value).to eq("$40")
    end
  end

  describe "#progress_fraction" do
    it "computes (current-start)/(target-start) for an increase metric" do
      metric = build(:metric, direction: "increase", start_value: 20, current_value: 25, target_value: 40)
      expect(metric.progress_fraction).to eq(0.25)
    end

    it "computes (start-current)/(start-target) for a decrease metric" do
      metric = build(:metric, direction: "decrease", start_value: 100, current_value: 75, target_value: 0)
      expect(metric.progress_fraction).to eq(0.25)
    end

    it "clamps below 0.0 when current has regressed past start" do
      metric = build(:metric, direction: "increase", start_value: 20, current_value: 10, target_value: 40)
      expect(metric.progress_fraction).to eq(0.0)
    end

    it "clamps above 1.0 when current has overshot target" do
      metric = build(:metric, direction: "increase", start_value: 20, current_value: 100, target_value: 40)
      expect(metric.progress_fraction).to eq(1.0)
    end

    it "clamps a decrease metric's overshoot past the target to 1.0" do
      metric = build(:metric, direction: "decrease", start_value: 100, current_value: -10, target_value: 0)
      expect(metric.progress_fraction).to eq(1.0)
    end

    it "is nil when target equals start (divide-by-zero guard)" do
      metric = build(:metric, direction: "increase", start_value: 20, current_value: 25, target_value: 20)
      expect(metric.progress_fraction).to be_nil
    end

    it "is nil when start_value or current_value is missing" do
      expect(build(:metric, start_value: nil, current_value: 25, target_value: 40).progress_fraction).to be_nil
      expect(build(:metric, start_value: 20, current_value: nil, target_value: 40).progress_fraction).to be_nil
    end
  end

  describe "#progress_percent" do
    it "rounds the fraction to a whole percent" do
      metric = build(:metric, direction: "increase", start_value: 0, current_value: 1, target_value: 3)
      expect(metric.progress_percent).to eq(33)
    end

    it "is nil when progress_fraction is nil" do
      metric = build(:metric, direction: "increase", start_value: 20, current_value: 25, target_value: 20)
      expect(metric.progress_percent).to be_nil
    end
  end

  describe "#remaining_to_target" do
    it "formats the delta to target using the metric's unit, for an increase metric" do
      metric = build(:metric, direction: "increase", current_value: 29, target_value: 100, unit: "$")
      expect(metric.remaining_to_target).to eq("$71")
    end

    it "formats the delta to target for a decrease metric" do
      metric = build(:metric, direction: "decrease", current_value: 8, target_value: 5, unit: "%")
      expect(metric.remaining_to_target).to eq("3%")
    end

    it "is nil once an increase metric has reached (or passed) its target" do
      metric = build(:metric, direction: "increase", current_value: 100, target_value: 100)
      expect(metric.remaining_to_target).to be_nil
      metric.current_value = 110
      expect(metric.remaining_to_target).to be_nil
    end

    it "is nil once a decrease metric has reached (or passed) its target" do
      metric = build(:metric, direction: "decrease", current_value: 5, target_value: 5)
      expect(metric.remaining_to_target).to be_nil
      metric.current_value = 2
      expect(metric.remaining_to_target).to be_nil
    end

    it "is nil when current_value is missing" do
      metric = build(:metric, current_value: nil, target_value: 40)
      expect(metric.remaining_to_target).to be_nil
    end
  end

  describe "#last_updated_at" do
    it "is nil with no metric_updates" do
      metric = create(:metric)
      expect(metric.last_updated_at).to be_nil
    end

    it "returns the most recent metric_update's created_at" do
      metric = create(:metric)
      user = create(:user, organization: metric.goal.organization)
      older = metric.metric_updates.create!(reported_by: user, value: 10, created_at: 2.days.ago)
      newer = metric.metric_updates.create!(reported_by: user, value: 20, created_at: 1.hour.ago)

      expect(metric.last_updated_at).to be_within(1.second).of(newer.created_at)
      expect(metric.last_updated_at).not_to eq(older.created_at)
    end
  end
end
