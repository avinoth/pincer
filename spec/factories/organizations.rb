FactoryBot.define do
  factory :organization do
    name { Faker::Company.name }
    provider { :slack }
    status { :active }
    time_zone { "UTC" }
    domain { Faker::Internet.domain_name }
    email { Faker::Internet.email }
    users_import_status { :pending }
  end
end
