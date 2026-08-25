class Organization < ApplicationRecord
  enum :provider, { slack: "slack" }, prefix: true
  enum :status, { active: "active", inactive: "inactive" }
  enum :users_import_status, {
    pending: "pending",
    in_progress: "in_progress",
    completed: "completed",
    failed: "failed"
  }, prefix: "users_import"

  validates :name, :provider, :status, :time_zone, presence: true

  belongs_to :owner, class_name: "User", optional: true
  has_one :slack_workspace, dependent: :destroy
  has_many :users, dependent: :destroy
  has_many :goals, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :memories, dependent: :destroy

  # Observability/audit logs, not org-defining state — these outlive the
  # org's deletion with the reference cleared, same on_delete: :nullify
  # policy as the user-attribution associations on User.
  has_many :llm_calls, dependent: :nullify
  has_many :slack_interactions, dependent: :nullify

  class << self
    def create_from_slack(slack_response)
      transaction do
        organization = create!(
          name: slack_response.team_name,
          provider: :slack,
          status: :active,
          time_zone: "UTC",
          domain: slack_response.email_domain,
        )

        organization.create_slack_workspace!(
          name: slack_response.team_name,
          identifier: slack_response.team_id,
          access_token: slack_response.access_token,
          refresh_token: slack_response.refresh_token,
          access_token_expires_at: slack_response.token_expires_at,
          bot_uid: slack_response.bot_id,
          installation_uid: slack_response.app_id,
        )

        organization
      end
    end
  end

  def update_details_from_slack(slack_response)
    transaction do
      active!
      slack_workspace.update_details_from_slack!(slack_response)
    end
  end
end
