FactoryBot.define do
  factory :slack_workspace do
    organization
    name { Faker::Company.name }
    sequence(:identifier) { |n| "T#{n}#{SecureRandom.hex(3).upcase}" }
    access_token { "xoxb-#{SecureRandom.hex(8)}" }
    refresh_token { "xoxe-#{SecureRandom.hex(8)}" }
    access_token_expires_at { 1.hour.from_now }
    installation_uid { "A#{SecureRandom.hex(3).upcase}" }
    bot_uid { "U#{SecureRandom.hex(3).upcase}" }

    trait :expired do
      access_token_expires_at { 1.hour.ago }
    end
  end
end
