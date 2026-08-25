FactoryBot.define do
  factory :metric do
    goal
    name { "Activation rate" }
    direction { "increase" }
    start_value { 20 }
    current_value { 20 }
    target_value { 40 }
    unit { "%" }
  end
end
