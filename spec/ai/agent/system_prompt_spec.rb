require "rails_helper"

RSpec.describe Ai::Agent::SystemPrompt do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { create(:organization, time_zone: "America/New_York") }
  let(:conversation) { create(:conversation, organization: organization) }
  let(:user) { create(:user, organization: organization) }
  let(:context) do
    Ai::Agent::ToolContext.new(conversation: conversation, organization: organization, user: user, agent_run: nil)
  end

  def build = described_class.build(context)

  it "includes the persona and today's date in the org's time zone" do
    travel_to Time.utc(2026, 8, 11, 2, 0, 0) do # 22:00 the previous day in America/New_York
      prompt = build

      expect(prompt).to include("You are Pincer")
      expect(prompt).to include("Today is 2026-08-10")
      expect(prompt).to include("America/New_York")
    end
  end

  it "includes the quarter convention" do
    expect(build).to include("Jan/Apr/Jul/Oct")
  end

  it "includes goal-form and memory-writing guidance" do
    expect(build).to include("show_goal_create_form")
    expect(build).to include("save_memory")
  end

  it "includes goal-display guidance directing the agent to show_goals/show_goal instead of markdown" do
    expect(build).to include("show_goals")
    expect(build).to include("show_goal")
    expect(build).to include("never re-list")
  end

  describe "Organization Memory" do
    it "lists active org-scoped memories with ids, newest first" do
      create(:memory, organization: organization, user: nil, content: "Older fact")
      newer = create(:memory, organization: organization, user: nil, content: "Quarters start in February")
      create(:memory, organization: organization, user: nil, content: "Inactive fact", active: false)
      create(:memory, organization: organization, user: create(:user, organization: organization),
        content: "Someone's personal fact")

      prompt = build

      expect(prompt).to include("Organization Memory:")
      expect(prompt).to include("- [#{newer.id}] Quarters start in February")
      expect(prompt).not_to include("Inactive fact")
      expect(prompt).not_to include("Someone's personal fact")
      expect(prompt.index("Quarters start in February")).to be < prompt.index("Older fact")
    end

    it "is omitted entirely when there are no org-scoped memories" do
      expect(build).not_to include("Organization Memory:")
    end

    it "caps the section at roughly 2000 characters, always keeping at least one entry" do
      15.times { |n| create(:memory, organization: organization, user: nil, content: "Fact number #{n} " * 10) }

      prompt = build
      section = prompt[/Organization Memory:\n(.*?)(\n\n|\z)/m, 1]

      expect(section.length).to be <= described_class::MEMORY_CHAR_CAP + 300
      expect(section.lines.count).to be >= 1
      expect(section.lines.count).to be < 15
    end
  end

  describe "User Memory" do
    it "lists only the turn author's own memories, with ids" do
      mine = create(:memory, organization: organization, user: user, content: "I prefer async updates")
      create(:memory, organization: organization, user: create(:user, organization: organization),
        content: "Someone else's preference")

      prompt = build

      expect(prompt).to include("User Memory:")
      expect(prompt).to include("- [#{mine.id}] I prefer async updates")
      expect(prompt).not_to include("Someone else's preference")
    end

    it "is omitted entirely when the user has no memories" do
      expect(build).not_to include("User Memory:")
    end
  end

  it "includes check-in capture guidance" do
    expect(build).to include("record_metric_update")
    expect(build).to include("complete_checkin")
  end

  describe "Your open check-ins" do
    it "lists the turn author's own notified/in_progress checkins, with ids and subject" do
      goal = create(:goal, organization: organization, owners: [ user ], title: "Grow activation")
      create(:metric, goal: goal, name: "Activation rate")
      metric_checkin = create(:checkin, organization: organization, user: user, goal: goal, status: "notified")
      initiative = create(:initiative, goal: goal, title: "Ship onboarding")
      initiative_checkin = create(:checkin, organization: organization, user: user, goal: goal,
                                  initiative: initiative, status: "in_progress")

      prompt = build

      expect(prompt).to include("Your open check-ins:")
      expect(prompt).to include("[#{metric_checkin.id}] Grow activation — metric: Activation rate")
      expect(prompt).to include("[#{initiative_checkin.id}] Grow activation — initiative: Ship onboarding")
    end

    it "excludes another user's checkins, and pending/completed/skipped/expired ones" do
      goal = create(:goal, organization: organization, owners: [ user ])
      create(:metric, goal: goal)
      other_user = create(:user, organization: organization)
      create(:checkin, organization: organization, user: other_user, goal: goal, status: "notified")
      %w[pending completed skipped expired].each_with_index do |status, i|
        create(:checkin, organization: organization, user: user, goal: goal, status: status,
                         period_key: "2026-08-#{20 + i}")
      end

      expect(build).not_to include("Your open check-ins:")
    end

    it "is omitted entirely when the user has no open checkins" do
      expect(build).not_to include("Your open check-ins:")
    end
  end

  describe "context hint" do
    it "includes it when present" do
      conversation.update!(context_hint: "user is viewing #launches")

      expect(build).to include("user is viewing #launches")
    end

    it "is omitted when absent" do
      expect(build).not_to include("Context:")
    end
  end
end
