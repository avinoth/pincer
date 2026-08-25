FactoryBot.define do
  factory :metric_update do
    metric
    reported_by { association :user, organization: metric.goal.organization }
    value { 25 }
  end
end
