# frozen_string_literal: true

module Ai
  module Agent
    module Tools
      # Base for every agent tool. Subclassing is the entire registration
      # mechanism (see .inherited) — a new tool file under app/ai/agent/tools/
      # that subclasses Base is automatically included in
      # Ai::Agent::Tools.build_all with no other wiring required.
      #
      # Every tool is constructed with an Ai::Agent::ToolContext, and every
      # tool's #execute is expected to rescue internally and return an
      # { error: "..." } shaped result rather than raise — a single tool
      # failing must not take down the whole agent run. See individual tools
      # for the DSL (.description, .param) inherited from RubyLLM::Tool.
      class Base < RubyLLM::Tool
        class << self
          def inherited(subclass)
            super
            Tools.registry << subclass
          end
        end

        attr_reader :context

        def initialize(context)
          super()
          @context = context
        end

        # RubyLLM::Tool#name derives a tool name from the class's fully
        # qualified name (Ai::Agent::Tools::ShowGoalCreateForm), which would
        # otherwise leak our module nesting into the tool name the LLM sees
        # (e.g. "ai-agent-tools-show_goal_create_form"). Use just the class's
        # own name instead.
        def name
          self.class.name.demodulize.underscore
        end

        # Translate our PENDING sentinel into a RubyLLM::Tool::Halt so the gem's
        # built-in tool loop STOPS after this tool instead of auto-continuing to
        # the model (see RubyLLM::Chat#handle_tool_calls: a Halt short-circuits
        # `halt_result || complete`). The runner recognises a Halt carrying
        # PENDING as "this run must pause for a human" and records the pending
        # tool call rather than persisting a tool result. Every other return
        # value (a normal result Hash, or an { error: } hash) flows through
        # untouched and the loop continues as usual.
        def call(args)
          result = super
          result == Tools::PENDING ? halt(Tools::PENDING) : result
        end
      end
    end
  end
end
