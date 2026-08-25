require "rails_helper"

RSpec.describe CompleteCheckin do
  let(:organization) { create(:organization) }
  let(:owner) { create(:user, organization: organization) }
  let(:goal) { create(:goal, organization: organization, owners: [ owner ]) }

  def call(**overrides)
    described_class.call({ checkins: [ checkin ], user: owner }.merge(overrides))
  end

  let(:checkin) { create(:checkin, organization: organization, user: owner, goal: goal, status: "notified") }

  it "flips the given checkins to completed and stamps completed_at" do
    result = call

    expect(result).to be_success
    expect(checkin.reload).to be_status_completed
    expect(checkin.completed_at).to be_present
  end

  it "completes multiple checkins in one call" do
    other_checkin = create(:checkin, organization: organization, user: owner, goal: goal,
                           initiative: create(:initiative, goal: goal), status: "notified")

    result = call(checkins: [ checkin, other_checkin ])

    expect(result).to be_success
    expect(checkin.reload).to be_status_completed
    expect(other_checkin.reload).to be_status_completed
  end

  it "fails, without completing anything, when a checkin belongs to a different user" do
    stranger = create(:user, organization: organization)

    result = call(user: stranger)

    expect(result).to be_failure
    expect(result.error).to be_present
    expect(checkin.reload).to be_status_notified
  end

  it "fails cleanly (never raises) with no checkins given" do
    expect {
      result = call(checkins: [])
      expect(result).to be_failure
    }.not_to raise_error
  end

  it "fails cleanly (never raises) on an invalid save" do
    allow(checkin).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(checkin))

    expect {
      result = call
      expect(result).to be_failure
    }.not_to raise_error
  end
end
