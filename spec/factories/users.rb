FactoryBot.define do
  factory :user do
    organization
    email { Faker::Internet.email }
    sequence(:provider_uid) { |n| "U#{n}#{SecureRandom.hex(3).upcase}" }
    full_name { Faker::Name.name }
    time_zone { "UTC" }
    role { :member }
    images { {} }

    trait :owner do
      role { :owner }
    end
  end
end
