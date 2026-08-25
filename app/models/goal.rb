# A goal (OKR objective). Created via the Slack Create Goal modal; owners are a
# many-to-many (goal_owners) distinct from the creator. See docs/data_model.md.
class Goal < ApplicationRecord
  # Terminal lifecycle statuses: a goal in either of these no longer accepts
  # new initiatives (see #accepts_initiatives? / .accepting_initiatives) — one
  # source of truth shared by both the agent tool guards and the modal's goal
  # option lists.
  TERMINAL_STATUSES = %w[completed ended].freeze

  enum :status, {
    not_started: "not_started",
    in_progress: "in_progress",
    completed: "completed",
    ended: "ended"
  }, prefix: "status"

  # AI-derived at summary time; unset at creation.
  enum :health, {
    on_track: "on_track",
    at_risk: "at_risk",
    off_track: "off_track"
  }, prefix: "health"

  # Orthogonal to the lifecycle `status` above: whether the goal has been
  # published yet, or is still a draft being worked on. Default comes from the
  # column ("published").
  enum :publishing_status, { draft: "draft", published: "published" }, prefix: "publishing"

  belongs_to :organization
  belongs_to :creator, class_name: "User", optional: true
  belongs_to :parent, class_name: "Goal", foreign_key: :parent_goal_id, optional: true

  has_many :sub_goals, class_name: "Goal", foreign_key: :parent_goal_id, dependent: :nullify
  has_many :goal_owners, dependent: :destroy
  has_many :owners, through: :goal_owners, source: :user

  # A goal has exactly one primary metric (enforced by a unique index on metrics).
  has_one :metric, dependent: :destroy
  has_many :initiatives, dependent: :destroy
  has_many :checkins, dependent: :destroy
  has_many :goal_updates, dependent: :destroy
  has_many :goal_notifications, dependent: :destroy

  validates :title, :status, :start_date, :end_date, presence: true
  validate :must_have_at_least_one_owner
  validate :publishing_status_not_reverting, on: :update
  validate :end_date_on_or_after_start_date

  scope :accepting_initiatives, -> { where.not(status: TERMINAL_STATUSES) }

  # Slack user id (User#provider_uid). Creator or any owner may modify the goal.
  def modifiable_by?(slack_user_id)
    return false if slack_user_id.blank?

    creator&.provider_uid == slack_user_id || owners.exists?(provider_uid: slack_user_id)
  end

  # A goal in a terminal lifecycle state (completed/ended) can't take on new
  # initiatives.
  def accepts_initiatives?
    !(status_completed? || status_ended?)
  end

  private

  def must_have_at_least_one_owner
    errors.add(:owners, "must include at least one owner") if owners.empty?
  end

  def end_date_on_or_after_start_date
    return if start_date.blank? || end_date.blank?

    errors.add(:end_date, "can't be before the start date") if end_date < start_date
  end

  # A published goal is final with respect to publishing: once published it can
  # never move back to draft.
  def publishing_status_not_reverting
    return unless publishing_status_changed?

    if publishing_status_was == "published" && publishing_draft?
      errors.add(:publishing_status, "can't move a published goal back to draft")
    end
  end
end
