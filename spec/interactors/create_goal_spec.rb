require "rails_helper"

RSpec.describe CreateGoal do
  let(:organization) { create(:organization) }
  let(:creator) { create(:user, organization: organization) }
  let(:owner) { create(:user, organization: organization) }

  def call(overrides = {})
    described_class.call({
      organization: organization,
      creator: creator,
      owners: [ owner ],
      title: "Grow activation",
      description: "desc",
      start_date: "2026-08-01",
      end_date: "2026-09-01",
      update_channel: "C1",
      summary_day: 5,
      summary_time: "17:00",
      parent: nil
    }.merge(overrides))
  end

  it "creates the goal and its owner rows" do
    result = call

    expect(result).to be_success
    goal = result.goal
    expect(goal).to be_persisted
    expect(goal.creator).to eq(creator)
    expect(goal.owners).to contain_exactly(owner)
    expect(goal.update_channel).to eq("C1")
    expect(goal.summary_day).to eq(5)
    expect(goal.summary_time).to eq("17:00")
    expect(goal).to be_status_in_progress
  end

  it "starts a goal whose start date is today or in the past as in progress" do
    expect(call(start_date: Date.current.to_s).goal).to be_status_in_progress
    expect(call(start_date: 1.week.ago.to_date.to_s).goal).to be_status_in_progress
  end

  it "marks a goal whose start date is in the future as not started" do
    expect(call(start_date: 1.week.from_now.to_date.to_s).goal).to be_status_not_started
  end

  it "fails and rolls back when there are no owners" do
    expect { @result = call(owners: []) }.not_to change(Goal, :count)

    expect(@result).to be_failure
    expect(GoalOwner.count).to eq(0)
  end

  it "links a parent goal when given" do
    parent = create(:goal, organization: organization)
    expect(call(parent: parent).goal.parent).to eq(parent)
  end

  it "publishes by default" do
    expect(call.goal).to be_publishing_published
  end

  it "saves as a draft when draft: true" do
    expect(call(draft: true).goal).to be_publishing_draft
  end

  it "fails and rolls back everything on invalid data" do
    expect { @result = call(title: nil) }.not_to change(Goal, :count)

    expect(@result).to be_failure
    expect(GoalOwner.count).to eq(0)
  end
end
