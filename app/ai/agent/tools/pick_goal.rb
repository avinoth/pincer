# frozen_string_literal: true

module Ai
  module Agent
    module Tools
      # Reusable fuzzy disambiguator: resolves a free-text goal reference (e.g.
      # "the activation goal") to a concrete goal_id before a tool like
      # edit_goal, which requires one, can run.
      #
      # Zero or a single match resolve inline, with no pause. Two-to-25 matches
      # can't be resolved by the model alone, so this pauses the run (Tools::PENDING)
      # and posts a Slack dropdown (Slack::Messages::AgentGoalPickerPrompt); the
      # run resumes once a human picks one (see
      # Slack::Interactions::AgentPickGoalSelection), and the chosen goal is fed
      # back into the transcript as if this tool had returned it directly.
      class PickGoal < Base
        MAX_CANDIDATES = 25

        description "Resolve a free-text or ambiguous goal reference (e.g. a title fragment) " \
                    "to a concrete goal, by fuzzy title match. A single match resolves " \
                    "immediately. Multiple matches pause this turn so the user can pick one " \
                    "from a dropdown — wait for that pick before proceeding. Use this before " \
                    "edit_goal whenever the user didn't give you an exact goal_id."

        param :query, desc: "Title or title fragment to search for, e.g. \"activation\"."

        def execute(query:)
          matches = context.organization.goals.where("title ILIKE ?", "%#{query}%")
            .order(:title).limit(MAX_CANDIDATES + 1).to_a

          return { error: "No goal matches '#{query}'. Ask the user to rephrase." } if matches.empty?
          return summarize(matches.first) if matches.size == 1
          return { error: "Too many goals match; ask the user to narrow." } if matches.size > MAX_CANDIDATES

          stash_candidates(matches)
          post_picker(query, matches)

          Tools::PENDING
        rescue StandardError => e
          { error: "Couldn't search goals for '#{query}': #{e.message}" }
        end

        private

        def summarize(goal)
          { id: goal.id, title: goal.title, start_date: goal.start_date, end_date: goal.end_date, status: goal.status }
        end

        # Candidate ids land under pending_tool_call["args"]; the runner is
        # responsible for the sibling id/name bookkeeping on the same hash, so
        # we merge rather than overwrite (see show_goal_create_form.rb#persist_draft).
        def stash_candidates(goals)
          agent_run = context.agent_run
          pending = (agent_run.pending_tool_call || {}).stringify_keys
          pending["args"] = { "candidate_goal_ids" => goals.map(&:id) }
          agent_run.update!(pending_tool_call: pending)
        end

        def post_picker(query, goals)
          prompt = Slack::Messages::AgentGoalPickerPrompt.new(agent_run: context.agent_run, query: query, goals: goals)

          Slack::Request::SendMessage.new(context.organization.slack_workspace).send_message(
            context.conversation.slack_channel_id,
            prompt.to_h.merge(thread_ts: context.conversation.slack_thread_ts),
          )
        end
      end
    end
  end
end
