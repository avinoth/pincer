FactoryBot.define do
  factory :initiative do
    goal
    creator { association :user, organization: goal.organization }
    title { "Ship onboarding revamp" }
    status { "proposed" }
  end
end
