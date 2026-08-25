FactoryBot.define do
  factory :agent_run do
    conversation
    status { "running" }
  end
end
