require "rails_helper"

RSpec.describe AddGoalUpdate do
  let(:organization) { create(:organization) }
  let(:goal_owner) { create(:user, organization: organization) }
  let(:goal) { create(:goal, organization: organization, owners: [ goal_owner ]) }

  def call(**overrides)
    described_class.call({ goal: goal, body: "Kickoff went well.", reported_by: goal_owner }.merge(overrides))
  end

  it "logs a GoalUpdate(kind: note) for the goal's owner" do
    result = call

    expect(result).to be_success
    goal_update = result.goal_update
    expect(goal_update).to be_kind_note
    expect(goal_update.goal).to eq(goal)
    expect(goal_update.body).to eq("Kickoff went well.")
    expect(goal_update.reported_by).to eq(goal_owner)
    expect(goal_update.initiative).to be_nil
  end

  it "scopes the note to an initiative when given" do
    initiative = create(:initiative, goal: goal)

    result = call(initiative: initiative)

    expect(result.goal_update.initiative).to eq(initiative)
  end

  it "allows an initiative owner (not just the goal's owner/creator) to add a note" do
    initiative_owner = create(:user, organization: organization)
    create(:initiative, goal: goal, owner: initiative_owner)

    result = call(reported_by: initiative_owner)

    expect(result).to be_success
  end

  it "links the GoalUpdate to the given checkin" do
    checkin = create(:checkin, organization: organization, user: goal_owner, goal: goal)

    result = call(checkin: checkin)

    expect(result.goal_update.checkin).to eq(checkin)
  end

  it "fails, without writing anything, for an unrelated user" do
    stranger = create(:user, organization: organization)

    result = call(reported_by: stranger)

    expect(result).to be_failure
    expect(result.error).to be_present
    expect(GoalUpdate.count).to eq(0)
  end

  it "fails cleanly (never raises) when the underlying save is invalid" do
    invalid_record = GoalUpdate.new
    invalid_record.errors.add(:base, "boom")
    allow(GoalUpdate).to receive(:create!)
      .and_raise(ActiveRecord::RecordInvalid.new(invalid_record))

    expect {
      result = call
      expect(result).to be_failure
      expect(result.error).to be_present
    }.not_to raise_error
  end
end
