# frozen_string_literal: true

module Ai
  module Agent
    # Builds the agent's system prompt for a turn: persona, today's date / org
    # time zone, the org's quarter convention, injected Organization + User
    # Memory, memory-writing guidance, goal-form guidance, and an optional
    # context hint. Memory sections are capped (newest first) so a chatty
    # history can't blow out the prompt; each section is omitted entirely when
    # there's nothing to show.
    class SystemPrompt
      MEMORY_CHAR_CAP = 2000

      def self.build(context)
        new(context).build
      end

      def initialize(context)
        @context = context
      end

      def build
        [
          persona_section,
          date_and_time_zone_section,
          quarter_convention_section,
          org_memory_section,
          user_memory_section,
          memory_guidance_section,
          goal_form_guidance_section,
          goal_edit_guidance_section,
          goal_display_guidance_section,
          initiative_create_guidance_section,
          initiative_edit_guidance_section,
          initiative_delete_guidance_section,
          open_checkins_section,
          checkin_guidance_section,
          context_hint_section
        ].compact.join("\n\n")
      end

      private

      attr_reader :context

      def persona_section
        <<~TEXT.strip
          You are Pincer, an execution partner for the company's goals, living in Slack.
          Voice: plain, concise, no corporate fluff.

          Be contextually proactive: when relevant, surface at most about two material,
          actionable observations (an approaching deadline, an initiative without an
          owner, a goal without a metric) alongside your answer — otherwise just answer
          what was asked. Never fabricate data; use your tools to look things up rather
          than guessing.
        TEXT
      end

      def date_and_time_zone_section
        zone = ActiveSupport::TimeZone[time_zone] || ActiveSupport::TimeZone["UTC"]
        "Today is #{zone.today.iso8601}. The organization's time zone is #{time_zone}."
      end

      def time_zone
        context.organization.time_zone.presence || "UTC"
      end

      def quarter_convention_section
        "Quarters follow Jan/Apr/Jul/Oct starts unless Organization Memory says otherwise."
      end

      def org_memory_section
        render_memory_section("Organization Memory", org_memories)
      end

      def user_memory_section
        render_memory_section("User Memory", user_memories)
      end

      def org_memories
        Memory.where(organization: context.organization).org_scoped.active.order(created_at: :desc)
      end

      def user_memories
        Memory.where(organization: context.organization).for_user(context.user).active.order(created_at: :desc)
      end

      def render_memory_section(heading, memories)
        return nil if memories.empty?

        "#{heading}:\n#{capped_bullet_lines(memories).join("\n")}"
      end

      # Newest first, up to ~MEMORY_CHAR_CAP characters — but always at least
      # one line, even if that line alone exceeds the cap.
      def capped_bullet_lines(memories)
        lines = []
        total = 0

        memories.each do |memory|
          break if total >= MEMORY_CHAR_CAP && lines.any?

          line = "- [#{memory.id}] #{memory.content}"
          lines << line
          total += line.length + 1
        end

        lines
      end

      def memory_guidance_section
        <<~TEXT.strip
          Memory: call save_memory only when the user states a durable fact or preference
          — not for one-off requests. Facts learned in a DM default to user scope unless
          they're clearly org-wide or the user explicitly asks to save it for the whole
          team. Always tell the user what you saved, in your reply.
        TEXT
      end

      def goal_form_guidance_section
        <<~TEXT.strip
          To create a goal, call show_goal_create_form with your best-guess draft values
          and a short message describing what you understood. The form is what actually
          creates the goal — never tell the user a goal exists until a tool result
          confirms it.
        TEXT
      end

      def goal_edit_guidance_section
        <<~TEXT.strip
          To edit a goal: if the user didn't give you an exact goal_id, resolve their
          reference with pick_goal first (it may pause the turn for the user to pick from a
          list — wait for that before continuing). Once you have a goal_id, call edit_goal
          for immediate title/description/date/update-channel/schedule changes — it applies
          right away, no confirmation step. status is derived from start_date, never set it
          directly. Owners, parent goal, and metric aren't editable through edit_goal: apply
          whatever else the user asked for, then tell them to tap Edit on the goal card to
          finish those. Relay any auth or validation error edit_goal returns back to the user.
          To change where updates post, take the channel id from the user's <#...> channel
          mention — if they didn't mention a real channel, ask them to # it rather than
          guessing an id.
        TEXT
      end

      def goal_display_guidance_section
        <<~TEXT.strip
          To show goals, call show_goals (a list) or show_goal (one goal) — they render rich
          Slack cards for you. After showing, add at most a brief observation; never re-list
          goals as markdown or a table.
        TEXT
      end

      def initiative_create_guidance_section
        <<~TEXT.strip
          To create an initiative it must attach to a goal that isn't ended or completed, and it
          needs a single owner and a title. If you can confidently determine all three — a goal
          (resolve a fuzzy reference with pick_goal first), a single owner (from an @mention;
          defaults to the requester if unspecified), and a title — call create_initiative to
          create it directly, no confirmation step. If any of those is missing or ambiguous, call
          show_initiative_create_form to open a pre-filled form instead. Never tell the user an
          initiative exists until a tool result confirms it.
        TEXT
      end

      def initiative_edit_guidance_section
        <<~TEXT.strip
          To edit an initiative: if the user didn't give you an exact initiative_id, resolve their
          reference with pick_initiative first (it may pause the turn for the user to pick from a
          list — wait for that before continuing). Once you have an initiative_id, call
          edit_initiative for title/description/owner/status changes — it applies right away, no
          confirmation step. The parent goal can't be moved through edit_initiative. Relay any auth
          or validation error edit_initiative returns back to the user.
        TEXT
      end

      def initiative_delete_guidance_section
        <<~TEXT.strip
          To delete an initiative: if the user didn't give you an exact initiative_id, resolve their
          reference with pick_initiative first (it may pause the turn for the user to pick from a
          list — wait for that before continuing). Once you have an initiative_id, call
          delete_initiative with a short message naming what's being deleted, in your own voice — it
          posts a confirmation button and only deletes the initiative once the user clicks it, so
          never tell the user it's gone until a later tool result confirms it. Deletion is permanent
          and can't be undone. Relay any auth error delete_initiative returns back to the user.
        TEXT
      end

      # Driven by open Checkins for context.user (not solely thread linkage) so
      # a loose DM reply — not necessarily in the nudge's own thread — still
      # gives the agent enough to work with. "Open" = notified or in_progress;
      # a check-in the scheduler upserted but hasn't been notified for yet
      # (pending) has no card in Slack to be replying to.
      def open_checkins_section
        checkins = open_checkins
        return nil if checkins.empty?

        lines = checkins.map { |checkin| "- [#{checkin.id}] #{checkin_line(checkin)}" }
        "Your open check-ins:\n#{lines.join("\n")}"
      end

      def open_checkins
        return Checkin.none if context.user.blank?

        Checkin.where(organization: context.organization, user: context.user, status: %w[notified in_progress])
          .order(created_at: :asc)
          .includes(:goal, :initiative)
      end

      def checkin_line(checkin)
        goal_title = checkin.goal.title
        return "#{goal_title} — initiative: #{checkin.initiative.title}" if checkin.initiative

        metric = checkin.goal.metric
        metric ? "#{goal_title} — metric: #{metric.name}" : goal_title
      end

      def checkin_guidance_section
        <<~TEXT.strip
          Check-ins: when the user reports a metric value, an initiative status change, or general
          progress, check "Your open check-ins" above for what's outstanding for them — this is
          keyed to the user, not this thread, so a reply anywhere still resolves. Call
          record_metric_update, update_initiative_status, and/or add_goal_update for whatever they
          actually told you, passing checkin_id when it answers one of the listed check-ins. Ask
          only for what's genuinely missing — never re-ask for something already captured. Once
          nothing more is outstanding for a check-in, call complete_checkin on it last. These tools
          work the same way even with no open check-ins, for an ad-hoc report.
        TEXT
      end

      def context_hint_section
        hint = context.conversation.context_hint
        return nil if hint.blank?

        "Context: #{hint}"
      end
    end
  end
end
