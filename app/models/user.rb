class User < ApplicationRecord
  enum :role, { member: "member", admin: "admin", owner: "owner" }

  validates :email, :organization_id, :provider_uid, :full_name, :time_zone, :role, presence: true

  belongs_to :organization

  has_many :checkins, dependent: :destroy
  has_many :goal_owners, dependent: :destroy
  has_many :owned_goals, through: :goal_owners, source: :goal

  # Attribution references, not ownership — these outlive the user: destroying
  # a User clears who's credited rather than deleting or blocking deletion of
  # the goal/initiative/update/log row itself. Mirrors initiatives.creator_id's
  # existing on_delete: :nullify policy at the DB level (see matching FKs in
  # db/schema.rb) — every has_many below is paired with an on_delete: :nullify
  # foreign key so raw SQL deletes stay consistent with these callbacks.
  has_many :created_goals, class_name: "Goal", foreign_key: :creator_id, inverse_of: :creator, dependent: :nullify
  has_many :created_initiatives, class_name: "Initiative", foreign_key: :creator_id, inverse_of: :creator, dependent: :nullify
  has_many :owned_initiatives, class_name: "Initiative", foreign_key: :owner_id, inverse_of: :owner, dependent: :nullify
  has_many :goal_updates, foreign_key: :reported_by_id, inverse_of: :reported_by, dependent: :nullify
  has_many :metric_updates, foreign_key: :reported_by_id, inverse_of: :reported_by, dependent: :nullify
  has_many :conversation_messages, dependent: :nullify
  has_many :memories, dependent: :nullify
  has_many :llm_calls, dependent: :nullify
  has_many :owned_organizations, class_name: "Organization", foreign_key: :owner_id, inverse_of: :owner, dependent: :nullify

  class << self
    def create_from_slack(slack_user, organization_id, role = "member")
      warn_invalid_time_zone(slack_user.tz)

      create(
        organization_id: organization_id,
        provider_uid: slack_user.uid,
        full_name: slack_user.full_name,
        time_zone: slack_user.tz,
        email: slack_user.email,
        role: role,
        images: slack_user.images,
      )
    end

    def sync_from_slack(slack_user, organization_id, role: :member)
      user = find_by(organization_id: organization_id, provider_uid: slack_user.uid)

      if user
        user.update_details_from_slack(slack_user)
        user
      else
        create_from_slack(slack_user, organization_id, role)
      end
    end

    def warn_invalid_time_zone(tz)
      return unless ActiveSupport::TimeZone.new(tz).nil?

      Bugsnag.notify("Invalid TimeZone from Slack") do |report|
        report.add_tab(:context, { tz: tz })
      end
    end
  end

  def update_details_from_slack(slack_user)
    self.class.warn_invalid_time_zone(slack_user.tz)

    update(
      full_name: slack_user.full_name,
      time_zone: slack_user.tz,
      email: slack_user.email,
      images: slack_user.images,
    )
  end

  def admin_or_owner?
    admin? || owner?
  end
end
