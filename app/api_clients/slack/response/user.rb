class Slack::Response::User < Slack::Response::Base
  def user
    Slack::Type::User.new(@response[:user])
  end

  def user_json
    @response[:user]
  end
end
