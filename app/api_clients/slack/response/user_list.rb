class Slack::Response::UserList < Slack::Response::Base
  def members
    Array(@response[:members]).map { |user| Slack::Type::User.new(user) }
  end

  def next_cursor
    @response.fetch(:response_metadata, {}).fetch(:next_cursor, nil).presence
  end

  def error?
    @response[:ok] == false
  end

  def error_message
    @response[:error]
  end
end
