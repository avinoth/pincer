require "rails_helper"

RSpec.describe Ai::Agent::Schemas::GoalSummarySchema do
  it "produces a strict JSON schema with health and body required fields" do
    schema = described_class.new.to_json_schema

    properties = schema[:schema][:properties]
    expect(properties[:health][:type]).to eq("string")
    expect(properties[:health][:enum]).to contain_exactly("on_track", "at_risk", "off_track")
    expect(properties[:body][:type]).to eq("string")
    expect(schema[:schema][:required]).to include(:health, :body)
  end
end
