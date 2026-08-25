FactoryBot.define do
  factory :conversation do
    organization
    slack_channel_id { "C0123" }
    sequence(:slack_thread_ts) { |n| "1700000000.%06d" % n }
    surface { "channel" }
    title { "Grow activation" }
  end
end
