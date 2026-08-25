FactoryBot.define do
  factory :slack_interaction do
    direction { "inbound" }
    event_type { "app_mention" }
    team_id { "T1" }
    channel_id { "C1" }
    slack_user_id { "U1" }
    ts { "1700000000.000100" }
    thread_ts { "1700000000.000100" }
    payload { {} }

    trait :outbound do
      direction { "outbound" }
      event_type { "chat.postMessage" }
      slack_user_id { nil }
      ok { true }
      response { { "ok" => true, "channel" => "C1", "ts" => "1700000000.000200" } }
    end
  end
end
