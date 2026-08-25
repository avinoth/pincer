FactoryBot.define do
  factory :goal_update do
    goal
    reported_by { association :user, organization: goal.organization }
    kind { "note" }
    body { "Checking in." }
  end
end
