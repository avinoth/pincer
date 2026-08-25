# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_20_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "agent_runs", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.decimal "cost", precision: 12, scale: 6
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.jsonb "error"
    t.integer "input_tokens"
    t.integer "output_tokens"
    t.jsonb "pending_tool_call"
    t.string "status", default: "running", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "created_at"], name: "index_agent_runs_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_agent_runs_on_conversation_id"
  end

  create_table "checkins", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "goal_id", null: false
    t.bigint "initiative_id"
    t.datetime "notified_at"
    t.bigint "organization_id", null: false
    t.string "period_key", null: false
    t.string "slack_channel_id"
    t.string "slack_thread_ts"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["goal_id", "user_id", "initiative_id", "period_key"], name: "index_checkins_on_initiative_subject_period", unique: true, where: "(initiative_id IS NOT NULL)"
    t.index ["goal_id", "user_id", "period_key"], name: "index_checkins_on_metric_subject_period", unique: true, where: "(initiative_id IS NULL)"
    t.index ["goal_id"], name: "index_checkins_on_goal_id"
    t.index ["initiative_id"], name: "index_checkins_on_initiative_id"
    t.index ["organization_id"], name: "index_checkins_on_organization_id"
    t.index ["user_id"], name: "index_checkins_on_user_id"
  end

  create_table "conversation_messages", force: :cascade do |t|
    t.text "content"
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "role", null: false
    t.string "slack_ts"
    t.string "tool_call_id"
    t.jsonb "tool_calls"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["conversation_id", "created_at"], name: "index_conversation_messages_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_conversation_messages_on_conversation_id"
    t.index ["user_id"], name: "index_conversation_messages_on_user_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.string "context_hint"
    t.datetime "created_at", null: false
    t.bigint "organization_id", null: false
    t.string "slack_channel_id", null: false
    t.string "slack_thread_ts", null: false
    t.string "surface", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["organization_id", "slack_channel_id", "slack_thread_ts"], name: "index_conversations_on_org_channel_thread", unique: true
    t.index ["organization_id"], name: "index_conversations_on_organization_id"
  end

  create_table "goal_notifications", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.bigint "goal_id", null: false
    t.string "health"
    t.string "kind", null: false
    t.string "period_key"
    t.datetime "posted_at"
    t.string "slack_channel_id"
    t.string "slack_thread_ts"
    t.datetime "updated_at", null: false
    t.index ["goal_id", "kind", "period_key"], name: "index_goal_notifications_on_weekly_period", unique: true, where: "((kind)::text = 'weekly'::text)"
    t.index ["goal_id", "kind"], name: "index_goal_notifications_on_start_end", unique: true, where: "((kind)::text = ANY ((ARRAY['start'::character varying, 'end'::character varying])::text[]))"
    t.index ["goal_id"], name: "index_goal_notifications_on_goal_id"
  end

  create_table "goal_owners", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "goal_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["goal_id", "user_id"], name: "index_goal_owners_on_goal_id_and_user_id", unique: true
    t.index ["goal_id"], name: "index_goal_owners_on_goal_id"
    t.index ["user_id"], name: "index_goal_owners_on_user_id"
  end

  create_table "goal_updates", force: :cascade do |t|
    t.text "body"
    t.bigint "checkin_id"
    t.datetime "created_at", null: false
    t.bigint "goal_id", null: false
    t.bigint "initiative_id"
    t.string "kind", null: false
    t.bigint "metric_update_id"
    t.bigint "reported_by_id"
    t.datetime "updated_at", null: false
    t.index ["checkin_id"], name: "index_goal_updates_on_checkin_id"
    t.index ["goal_id"], name: "index_goal_updates_on_goal_id"
    t.index ["initiative_id"], name: "index_goal_updates_on_initiative_id"
    t.index ["metric_update_id"], name: "index_goal_updates_on_metric_update_id"
    t.index ["reported_by_id"], name: "index_goal_updates_on_reported_by_id"
  end

  create_table "goals", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.text "description"
    t.date "end_date"
    t.string "health"
    t.bigint "organization_id", null: false
    t.bigint "parent_goal_id"
    t.string "publishing_status", default: "published", null: false
    t.date "start_date"
    t.string "status", default: "in_progress", null: false
    t.integer "summary_day"
    t.string "summary_time"
    t.string "title", null: false
    t.string "update_channel"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_goals_on_creator_id"
    t.index ["organization_id"], name: "index_goals_on_organization_id"
    t.index ["parent_goal_id"], name: "index_goals_on_parent_goal_id"
    t.index ["publishing_status"], name: "index_goals_on_publishing_status"
    t.index ["status"], name: "index_goals_on_status"
  end

  create_table "good_job_batches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "callback_priority"
    t.text "callback_queue_name"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "discarded_at"
    t.datetime "enqueued_at"
    t.datetime "finished_at"
    t.datetime "jobs_finished_at"
    t.text "on_discard"
    t.text "on_finish"
    t.text "on_success"
    t.jsonb "serialized_properties"
    t.datetime "updated_at", null: false
  end

  create_table "good_job_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "active_job_id", null: false
    t.datetime "created_at", null: false
    t.interval "duration"
    t.text "error"
    t.text "error_backtrace", array: true
    t.integer "error_event", limit: 2
    t.datetime "finished_at"
    t.text "job_class"
    t.uuid "process_id"
    t.text "queue_name"
    t.datetime "scheduled_at"
    t.jsonb "serialized_params"
    t.datetime "updated_at", null: false
    t.index ["active_job_id", "created_at"], name: "index_good_job_executions_on_active_job_id_and_created_at"
    t.index ["process_id", "created_at"], name: "index_good_job_executions_on_process_id_and_created_at"
  end

  create_table "good_job_processes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "lock_type", limit: 2
    t.jsonb "state"
    t.datetime "updated_at", null: false
  end

  create_table "good_job_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "key"
    t.datetime "updated_at", null: false
    t.jsonb "value"
    t.index ["key"], name: "index_good_job_settings_on_key", unique: true
  end

  create_table "good_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "active_job_id"
    t.uuid "batch_callback_id"
    t.uuid "batch_id"
    t.text "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "cron_at"
    t.text "cron_key"
    t.text "error"
    t.integer "error_event", limit: 2
    t.integer "executions_count"
    t.datetime "finished_at"
    t.boolean "is_discrete"
    t.text "job_class"
    t.text "labels", array: true
    t.integer "lock_type", limit: 2
    t.datetime "locked_at"
    t.uuid "locked_by_id"
    t.datetime "performed_at"
    t.integer "priority"
    t.text "queue_name"
    t.uuid "retried_good_job_id"
    t.datetime "scheduled_at"
    t.jsonb "serialized_params"
    t.datetime "updated_at", null: false
    t.index ["active_job_id", "created_at"], name: "index_good_jobs_on_active_job_id_and_created_at"
    t.index ["batch_callback_id"], name: "index_good_jobs_on_batch_callback_id", where: "(batch_callback_id IS NOT NULL)"
    t.index ["batch_id"], name: "index_good_jobs_on_batch_id", where: "(batch_id IS NOT NULL)"
    t.index ["concurrency_key", "created_at"], name: "index_good_jobs_on_concurrency_key_and_created_at"
    t.index ["concurrency_key"], name: "index_good_jobs_on_concurrency_key_when_unfinished", where: "(finished_at IS NULL)"
    t.index ["created_at"], name: "index_good_jobs_on_created_at"
    t.index ["cron_key", "created_at"], name: "index_good_jobs_on_cron_key_and_created_at_cond", where: "(cron_key IS NOT NULL)"
    t.index ["cron_key", "cron_at"], name: "index_good_jobs_on_cron_key_and_cron_at_cond", unique: true, where: "(cron_key IS NOT NULL)"
    t.index ["finished_at"], name: "index_good_jobs_jobs_on_finished_at_only", where: "(finished_at IS NOT NULL)"
    t.index ["finished_at"], name: "index_good_jobs_on_discarded", order: :desc, where: "((finished_at IS NOT NULL) AND (error IS NOT NULL))"
    t.index ["id"], name: "index_good_jobs_on_unfinished_or_errored", where: "((finished_at IS NULL) OR (error IS NOT NULL))"
    t.index ["job_class"], name: "index_good_jobs_on_job_class"
    t.index ["labels"], name: "index_good_jobs_on_labels", where: "(labels IS NOT NULL)", using: :gin
    t.index ["locked_by_id"], name: "index_good_jobs_on_locked_by_id", where: "(locked_by_id IS NOT NULL)"
    t.index ["priority", "created_at"], name: "index_good_job_jobs_for_candidate_lookup", where: "(finished_at IS NULL)"
    t.index ["priority", "created_at"], name: "index_good_jobs_jobs_on_priority_created_at_when_unfinished", order: { priority: "DESC NULLS LAST" }, where: "(finished_at IS NULL)"
    t.index ["priority", "scheduled_at", "id"], name: "index_good_jobs_for_candidate_dequeue_unlocked", where: "((finished_at IS NULL) AND (locked_by_id IS NULL))"
    t.index ["priority", "scheduled_at", "id"], name: "index_good_jobs_on_priority_scheduled_at_unfinished", where: "(finished_at IS NULL)"
    t.index ["priority", "scheduled_at"], name: "index_good_jobs_on_priority_scheduled_at_unfinished_unlocked", where: "((finished_at IS NULL) AND (locked_by_id IS NULL))"
    t.index ["queue_name", "scheduled_at", "id"], name: "index_good_jobs_on_queue_name_priority_scheduled_at_unfinished", where: "(finished_at IS NULL)"
    t.index ["queue_name", "scheduled_at"], name: "index_good_jobs_on_queue_name_and_scheduled_at", where: "(finished_at IS NULL)"
    t.index ["queue_name"], name: "index_good_jobs_on_queue_name"
    t.index ["scheduled_at", "queue_name"], name: "index_good_jobs_on_scheduled_at_and_queue_name"
    t.index ["scheduled_at"], name: "index_good_jobs_on_scheduled_at", where: "(finished_at IS NULL)"
  end

  create_table "initiatives", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.text "description"
    t.bigint "goal_id", null: false
    t.bigint "owner_id"
    t.string "status", default: "proposed", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_initiatives_on_creator_id"
    t.index ["goal_id"], name: "index_initiatives_on_goal_id"
    t.index ["owner_id"], name: "index_initiatives_on_owner_id"
  end

  create_table "llm_calls", force: :cascade do |t|
    t.bigint "agent_run_id"
    t.integer "completion_tokens"
    t.decimal "cost", precision: 12, scale: 6
    t.datetime "created_at", null: false
    t.text "error"
    t.integer "latency_ms"
    t.string "model"
    t.bigint "organization_id"
    t.jsonb "parsed_output", default: {}, null: false
    t.integer "prompt_tokens"
    t.string "provider"
    t.jsonb "raw_response", default: {}, null: false
    t.boolean "repaired", default: false, null: false
    t.jsonb "request_messages", default: {}, null: false
    t.string "status", null: false
    t.string "task", null: false
    t.decimal "temperature", precision: 3, scale: 2
    t.integer "total_tokens"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["agent_run_id"], name: "index_llm_calls_on_agent_run_id"
    t.index ["organization_id"], name: "index_llm_calls_on_organization_id"
    t.index ["task", "status"], name: "index_llm_calls_on_task_and_status"
    t.index ["user_id"], name: "index_llm_calls_on_user_id"
  end

  create_table "memories", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "category"
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.bigint "organization_id", null: false
    t.bigint "source_conversation_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["organization_id", "active"], name: "index_memories_on_organization_id_and_active", where: "active"
    t.index ["organization_id"], name: "index_memories_on_organization_id"
    t.index ["source_conversation_id"], name: "index_memories_on_source_conversation_id"
    t.index ["user_id"], name: "index_memories_on_user_id"
  end

  create_table "metric_updates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "metric_id", null: false
    t.text "note"
    t.bigint "reported_by_id"
    t.datetime "updated_at", null: false
    t.decimal "value", precision: 15, scale: 4, null: false
    t.index ["metric_id"], name: "index_metric_updates_on_metric_id"
    t.index ["reported_by_id"], name: "index_metric_updates_on_reported_by_id"
  end

  create_table "metrics", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "current_value", precision: 15, scale: 4
    t.string "direction", null: false
    t.bigint "goal_id", null: false
    t.string "name", null: false
    t.decimal "start_value", precision: 15, scale: 4
    t.decimal "target_value", precision: 15, scale: 4, null: false
    t.string "unit"
    t.datetime "updated_at", null: false
    t.index ["goal_id"], name: "index_metrics_on_goal_id", unique: true
  end

  create_table "organizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "domain"
    t.string "email"
    t.string "name", null: false
    t.bigint "owner_id"
    t.string "provider", null: false
    t.string "status", null: false
    t.string "time_zone", null: false
    t.datetime "updated_at", null: false
    t.string "users_import_status", default: "pending", null: false
  end

  create_table "slack_interactions", force: :cascade do |t|
    t.string "channel_id"
    t.datetime "created_at", null: false
    t.string "direction", null: false
    t.text "error"
    t.string "event_type"
    t.boolean "ok"
    t.bigint "organization_id"
    t.jsonb "payload", default: {}, null: false
    t.jsonb "response"
    t.integer "retry_num"
    t.string "retry_reason"
    t.string "slack_user_id"
    t.string "team_id"
    t.string "thread_ts"
    t.string "ts"
    t.datetime "updated_at", null: false
    t.index ["channel_id", "ts"], name: "index_slack_interactions_on_channel_id_and_ts"
    t.index ["created_at"], name: "index_slack_interactions_on_created_at"
    t.index ["direction"], name: "index_slack_interactions_on_direction"
    t.index ["event_type"], name: "index_slack_interactions_on_event_type"
    t.index ["organization_id"], name: "index_slack_interactions_on_organization_id"
    t.index ["team_id"], name: "index_slack_interactions_on_team_id"
    t.index ["thread_ts"], name: "index_slack_interactions_on_thread_ts"
  end

  create_table "slack_workspaces", force: :cascade do |t|
    t.string "access_token", null: false
    t.datetime "access_token_expires_at"
    t.string "bot_uid"
    t.datetime "created_at", null: false
    t.string "identifier", null: false
    t.string "installation_uid"
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.string "refresh_token", null: false
    t.datetime "updated_at", null: false
    t.index ["identifier"], name: "index_slack_workspaces_on_identifier"
    t.index ["organization_id"], name: "workspace_unique_organization_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "full_name", null: false
    t.datetime "greeted_at"
    t.jsonb "images"
    t.bigint "organization_id", null: false
    t.string "provider_uid", null: false
    t.string "role", null: false
    t.string "time_zone", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_users_on_created_at"
    t.index ["organization_id", "provider_uid"], name: "index_users_on_organization_id_and_provider_uid", unique: true
    t.index ["organization_id"], name: "index_users_on_organization_id"
  end

  add_foreign_key "agent_runs", "conversations"
  add_foreign_key "checkins", "goals"
  add_foreign_key "checkins", "initiatives"
  add_foreign_key "checkins", "organizations"
  add_foreign_key "checkins", "users"
  add_foreign_key "conversation_messages", "conversations"
  add_foreign_key "conversation_messages", "users", on_delete: :nullify
  add_foreign_key "conversations", "organizations"
  add_foreign_key "goal_notifications", "goals"
  add_foreign_key "goal_owners", "goals"
  add_foreign_key "goal_owners", "users"
  add_foreign_key "goal_updates", "checkins"
  add_foreign_key "goal_updates", "goals"
  add_foreign_key "goal_updates", "initiatives"
  add_foreign_key "goal_updates", "metric_updates"
  add_foreign_key "goal_updates", "users", column: "reported_by_id", on_delete: :nullify
  add_foreign_key "goals", "goals", column: "parent_goal_id"
  add_foreign_key "goals", "organizations"
  add_foreign_key "goals", "users", column: "creator_id", on_delete: :nullify
  add_foreign_key "initiatives", "goals"
  add_foreign_key "initiatives", "users", column: "creator_id", on_delete: :nullify
  add_foreign_key "initiatives", "users", column: "owner_id", on_delete: :nullify
  add_foreign_key "llm_calls", "agent_runs"
  add_foreign_key "llm_calls", "organizations", on_delete: :nullify
  add_foreign_key "llm_calls", "users", on_delete: :nullify
  add_foreign_key "memories", "conversations", column: "source_conversation_id"
  add_foreign_key "memories", "organizations"
  add_foreign_key "memories", "users", on_delete: :nullify
  add_foreign_key "metric_updates", "metrics"
  add_foreign_key "metric_updates", "users", column: "reported_by_id", on_delete: :nullify
  add_foreign_key "metrics", "goals"
  add_foreign_key "organizations", "users", column: "owner_id", on_delete: :nullify
  add_foreign_key "slack_interactions", "organizations", on_delete: :nullify
  add_foreign_key "slack_workspaces", "organizations"
  add_foreign_key "users", "organizations"
end
