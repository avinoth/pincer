# frozen_string_literal: true

module Ai
  module Agent
    # Everything a tool needs about the turn it's executing in, handed to every
    # tool at construction (see Ai::Agent::Tools::Base#initialize):
    #
    #   conversation — the Conversation (1:1 Slack thread) this turn belongs to.
    #   organization — the Conversation's Organization; tools scope every query
    #                  to it.
    #   user         — the User who authored *this* turn (not necessarily the
    #                  only participant in the thread) — e.g. save_memory's
    #                  default scope and forget_memory's ownership check key off
    #                  this, not the conversation as a whole.
    #   agent_run    — the AgentRun executing the current turn; tools that need
    #                  to pause (show_goal_create_form) write to its
    #                  pending_tool_call column.
    ToolContext = Struct.new(:conversation, :organization, :user, :agent_run, keyword_init: true)
  end
end
