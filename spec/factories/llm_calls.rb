FactoryBot.define do
  factory :llm_call do
    organization
    task { "agent_turn" }
    status { "success" }
  end
end
