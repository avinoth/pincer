require "rails_helper"

RSpec.describe UpdateGoal do
  let(:organization) { create(:organization) }

  def call(goal, attributes: {}, publish: false)
    described_class.call(goal: goal, attributes: attributes, publish: publish)
  end

  it "updates the given attributes" do
    goal = create(:goal, organization: organization, title: "Old title")

    result = call(goal, attributes: { title: "New title", description: "New desc" })

    expect(result).to be_success
    expect(goal.reload.title).to eq("New title")
    expect(goal.description).to eq("New desc")
  end

  it "replaces owners when given" do
    goal = create(:goal, organization: organization)
    new_owner = create(:user, organization: organization)

    result = call(goal, attributes: { owners: [ new_owner ] })

    expect(result).to be_success
    expect(goal.reload.owners).to contain_exactly(new_owner)
  end

  it "recomputes lifecycle status from a changed start_date" do
    goal = create(:goal, organization: organization, status: "not_started", start_date: 1.week.from_now.to_date)
    expect(goal).to be_status_not_started

    call(goal, attributes: { start_date: Date.current })

    expect(goal.reload).to be_status_in_progress
  end

  it "publishes a draft goal when publish: true" do
    goal = create(:goal, organization: organization, publishing_status: "draft")

    result = call(goal, publish: true)

    expect(result).to be_success
    expect(goal.reload).to be_publishing_published
  end

  it "supports one-click publish with no attribute changes" do
    goal = create(:goal, organization: organization, publishing_status: "draft", title: "Unchanged")

    result = call(goal, attributes: {}, publish: true)

    expect(result).to be_success
    expect(goal.reload.title).to eq("Unchanged")
    expect(goal).to be_publishing_published
  end

  it "never sets publishing_status to draft" do
    goal = create(:goal, organization: organization, publishing_status: "draft")

    call(goal, publish: false)

    expect(goal.reload).to be_publishing_draft
  end

  it "fails and does not persist when reverting a published goal to draft" do
    goal = create(:goal, organization: organization, publishing_status: "published", title: "Published goal")

    result = call(goal, attributes: { publishing_status: "draft" })

    expect(result).to be_failure
    expect(goal.reload).to be_publishing_published
  end

  it "fails on invalid attributes" do
    goal = create(:goal, organization: organization)

    result = call(goal, attributes: { title: nil })

    expect(result).to be_failure
    expect(goal.reload.title).not_to be_nil
  end
end
