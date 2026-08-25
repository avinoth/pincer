FactoryBot.define do
  factory :conversation_message do
    conversation
    role { "user" }
    content { "create a goal to grow activation" }
  end
end
