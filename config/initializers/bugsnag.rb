Bugsnag.configure do |config|
  # API key comes from the environment (it was previously hardcoded — don't).
  config.api_key = ENV["BUGSNAG_API_KEY"]
  config.release_stage = Rails.env
  config.notify_release_stages = %w[production staging]
end
