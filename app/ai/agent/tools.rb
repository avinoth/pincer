# frozen_string_literal: true

module Ai
  module Agent
    # Namespace + registry for the agent's tools. Concrete tools live in
    # app/ai/agent/tools/*.rb and register themselves automatically by
    # inheriting from Ai::Agent::Tools::Base (see Base.inherited) — dropping in
    # a new tool class is enough, nothing else to wire up.
    module Tools
      # Sentinel a tool's #execute can return to signal "this run must pause —
      # a human needs to interact with something we just posted to Slack (e.g.
      # a form) before the conversation can continue." The runner checks every
      # tool result for this sentinel and, when it sees it, persists
      # AgentRun#pending_tool_call and exits instead of continuing the loop; a
      # later Slack interaction resumes the run with the real tool result (see
      # show_goal_create_form.rb).
      PENDING = :pending_human

      class << self
        # Every tool class that has inherited from Base, in definition order.
        # Only classes Zeitwerk has actually loaded show up here, which is why
        # this — like build_all — eager-loads app/ai/agent/tools first: outside
        # `config.eager_load = true` (production, or CI), a tool file nobody
        # has referenced yet simply hasn't run its `inherited` hook, so the
        # registry would otherwise silently miss it depending on load order.
        def registry
          ensure_tools_loaded!
          @registry ||= []
        end

        # One freshly-constructed instance of every registered tool, bound to
        # this turn's context. This is what the runner hands to
        # RubyLLM::Chat#with_tools for each turn — tool *instances*, not
        # classes, since each needs the context at construction.
        def build_all(context)
          registry.map { |tool_class| tool_class.new(context) }
        end

        private

        # Idempotent and re-entrant-safe: eager-loading tools/ makes each tool
        # file's `Base.inherited` hook fire, which calls back into `registry`
        # (to push itself on) — the `@loading` guard makes that inner call a
        # no-op instead of recursing back into eager_load_dir.
        def ensure_tools_loaded!
          return if @loading || @tools_loaded

          @loading = true
          Rails.autoloaders.main.eager_load_dir(File.join(__dir__, "tools"))
          @tools_loaded = true
        ensure
          @loading = false
        end
      end
    end
  end
end
