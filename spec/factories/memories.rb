FactoryBot.define do
  factory :memory do
    organization
    content { "Prefers weekly check-ins on Fridays" }
    category { "preference" }
    active { true }
  end
end
