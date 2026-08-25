class Slack::Type::User
  IMAGE_DIMENSIONS = %w[24 32 48 72 192 512].freeze

  def initialize(user)
    @user = user
  end

  def user_json
    @user
  end

  def uid
    @user[:id]
  end

  def full_name
    @user[:real_name] || @user[:name]
  end

  def email
    @user.dig(:profile, :email)
  end

  def tz
    @user[:tz].presence
  end

  def is_bot?
    @user[:is_bot] == true || uid == "USLACKBOT"
  end

  def is_deleted?
    @user[:deleted] == true
  end

  def images
    IMAGE_DIMENSIONS.each_with_object({}) do |dimension, hsh|
      hsh["image_#{dimension}"] = @user.dig(:profile, "image_#{dimension}")
    end
  end

  def avatar
    images["image_24"]
  end
end
