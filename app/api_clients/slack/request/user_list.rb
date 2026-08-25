class Slack::Request::UserList < Slack::Request::Base
  USER_FETCH_LIMIT = 200

  def initialize(workspace, cursor: nil, cache: true)
    super(workspace)
    @cache = cache
    @cursor = cursor
  end

  def get
    response = @cache ? cached_request : make_request

    Slack::Response::UserList.new(response)
  end

  protected

  def make_request
    client.users_list(cursor: @cursor, limit: USER_FETCH_LIMIT)
  rescue => e
    Bugsnag.notify(e, { cursor: @cursor, workspace_id: @workspace.id })
    nil
  end

  def cache_key
    "#{@workspace.id}:#{@cursor}:UserList.get"
  end
end
