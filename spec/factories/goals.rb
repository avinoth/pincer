FactoryBot.define do
  factory :goal do
    organization
    creator { association :user, organization: organization }
    title { "Grow activation" }
    status { "in_progress" }
    start_date { "2026-08-01" }
    end_date { "2026-09-01" }
    summary_day { 5 }
    summary_time { "17:00" }

    # A goal is invalid without an owner; give it one for the create strategy
    # (a persisted org is required to build the owner). build(:goal) callers that
    # need a valid record can pass owners explicitly.
    after(:build) do |goal|
      if goal.owners.empty? && goal.organization&.persisted?
        goal.owners = [ create(:user, organization: goal.organization) ]
      end
    end
  end
end
