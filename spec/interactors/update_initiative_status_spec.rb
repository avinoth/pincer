require "rails_helper"

RSpec.describe UpdateInitiativeStatus do
  let(:organization) { create(:organization) }
  let(:goal_owner) { create(:user, organization: organization) }
  let(:goal) { create(:goal, organization: organization, owners: [ goal_owner ]) }
  let(:initiative_owner) { create(:user, organization: organization) }
  let(:initiative) { create(:initiative, goal: goal, owner: initiative_owner, status: "in_progress") }

  def call(**overrides)
    described_class.call({ initiative: initiative, status: "done", reported_by: initiative_owner }.merge(overrides))
  end

  it "updates the initiative's status and logs a GoalUpdate(kind: initiative_status)" do
    result = call

    expect(result).to be_success
    expect(initiative.reload).to be_status_done

    goal_update = result.goal_update
    expect(goal_update).to be_kind_initiative_status
    expect(goal_update.goal).to eq(goal)
    expect(goal_update.initiative).to eq(initiative)
    expect(goal_update.reported_by).to eq(initiative_owner)
    expect(goal_update.body).to include("in_progress").and include("done")
  end

  it "also allows the parent goal's owner to update it" do
    result = call(reported_by: goal_owner)

    expect(result).to be_success
    expect(initiative.reload).to be_status_done
  end

  it "links the GoalUpdate to the given checkin" do
    checkin = create(:checkin, organization: organization, user: initiative_owner, goal: goal, initiative: initiative)

    result = call(checkin: checkin)

    expect(result.goal_update.checkin).to eq(checkin)
  end

  it "fails, without changing the status, for an unrelated user" do
    stranger = create(:user, organization: organization)

    result = call(reported_by: stranger)

    expect(result).to be_failure
    expect(result.error).to be_present
    expect(initiative.reload).to be_status_in_progress
    expect(GoalUpdate.count).to eq(0)
  end

  it "fails cleanly (never raises) on an invalid status" do
    expect {
      result = call(status: "not_a_real_status")
      expect(result).to be_failure
    }.not_to raise_error

    expect(initiative.reload).to be_status_in_progress
  end
end
