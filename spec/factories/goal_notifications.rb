FactoryBot.define do
  factory :goal_notification do
    goal
    kind { "weekly" }
    period_key { "2026-08-20" }
  end
end
