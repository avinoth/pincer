RailsAdmin.config do |config|
  config.asset_source = :sprockets

  # Shared ENV-based Basic Auth credential (see api/lib/admin_auth.rb). Fails
  # closed: with ADMIN_USERNAME/ADMIN_PASSWORD unset, this always rejects.
  config.authenticate_with do
    authenticate_or_request_with_http_basic("Admin") { |u, p| AdminAuth.valid?(u, p) }
  end

  # GoodJob ships its own dashboard for its own tables — keep them out of the
  # RailsAdmin nav entirely. Verified via:
  #   bin/rails runner 'Rails.application.eager_load!; puts ActiveRecord::Base.descendants.map(&:name).sort'
  # GoodJob::Execution and GoodJob::DiscreteExecution both map to the same
  # good_job_executions table (legacy/current class pair); GoodJob::BaseRecord
  # is the abstract base. All are excluded regardless of which ones RailsAdmin
  # would actually surface, since excluding an unreachable name is a no-op.
  config.excluded_models = %w[
    GoodJob::BaseRecord
    GoodJob::BatchRecord
    GoodJob::DiscreteExecution
    GoodJob::Execution
    GoodJob::Job
    GoodJob::Process
    GoodJob::Setting
  ]

  ### Popular gems integration

  ## == Devise ==
  # config.authenticate_with do
  #   warden.authenticate! scope: :user
  # end
  # config.current_user_method(&:current_user)

  ## == CancanCan ==
  # config.authorize_with :cancancan

  ## == Pundit ==
  # config.authorize_with :pundit

  ## == PaperTrail ==
  # config.audit_with :paper_trail, 'User', 'PaperTrail::Version' # PaperTrail >= 3.0.0

  ### More at https://github.com/railsadminteam/rails_admin/wiki/Base-configuration

  ## == Gravatar integration ==
  ## To disable Gravatar integration in Navigation Bar set to false
  # config.show_gravatar = true

  # Agent-generated operational state — ad-hoc edits/deletes risk corrupting
  # live agent context, so these models are read-only (index/show/search/
  # export only, no new/edit/delete/bulk_delete).
  read_only_models = %w[LlmCall Memory Conversation ConversationMessage AgentRun]

  config.actions do
    dashboard                     # mandatory
    index                         # mandatory
    new do
      except read_only_models
    end
    export
    bulk_delete do
      except read_only_models
    end
    show
    edit do
      except read_only_models
    end
    delete do
      except read_only_models
    end
    show_in_app

    ## With an audit adapter, you can add:
    # history_index
    # history_show
  end

  # RailsAdmin's quick-search box (the "query" param) runs against every
  # queryable field by default, including jsonb columns — and for jsonb it
  # tries to JSON-parse the search term to compare, raising JSON::ParserError
  # (500) for any plain-text search. Verified live: searching "Vinoth" on the
  # Users index 500'd with that exact exception, tracing through
  # RailsAdmin::Config::Fields::Types::Json#parse_value. Disable both
  # `queryable` (gates the quick-search field set — see
  # RailsAdmin::Adapters::ActiveRecord#query_scope's default `fields` arg)
  # and `searchable` (gates the separate advanced-filter widget) on every
  # jsonb column across the app's models (found via `grep 't.jsonb' db/
  # schema.rb`, excluding GoodJob's own excluded tables).
  {
    "User" => %i[images],
    "SlackInteraction" => %i[payload response],
    "AgentRun" => %i[error pending_tool_call],
    "ConversationMessage" => %i[tool_calls],
    "LlmCall" => %i[parsed_output raw_response request_messages]
  }.each do |model_name, field_names|
    config.model model_name do
      field_names.each do |field_name|
        configure field_name do
          queryable false
          searchable false
        end
      end
    end
  end

  # SlackWorkspace holds the only two real secret columns in the schema
  # (access_token/refresh_token). Mask them everywhere they'd otherwise be
  # rendered (show/list/export) and drop them from the create/edit forms
  # entirely rather than showing a disabled field with the real value.
  config.model "SlackWorkspace" do
    %i[access_token refresh_token].each do |secret_field|
      configure secret_field do
        formatted_value { "•" * 12 }
      end
    end

    edit do
      exclude_fields :access_token, :refresh_token
    end
  end
end
