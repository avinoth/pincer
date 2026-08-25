FactoryBot.define do
  factory :checkin do
    organization
    user { association :user, organization: organization }
    goal { association :goal, organization: organization }
    status { "pending" }
    period_key { "2026-08-20" }
  end
end
