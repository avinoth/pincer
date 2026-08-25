# frozen_string_literal: true

# RubyLLM::Schema (structured-output DSL) ships as the transitive ruby_llm-schema
# gem, which Bundler does not auto-require. Load it here so task classes can
# reference RubyLLM::Schema at load time.
require "ruby_llm/schema"

# Pincer talks to LLMs through RubyLLM, routed via OpenRouter. Each AI task
# (see app/ai/task.rb) declares a semantic model *role* rather than a concrete
# slug; the role -> slug map lives here and is env-overridable, so "which model
# does classification use?" is answerable in one place and swappable per
# environment without touching task code.
RubyLLM.configure do |config|
  config.openrouter_api_key = ENV["OPENROUTER_API_KEY"]
end

# Semantic role -> OpenRouter model slug.
#   :lightweight — high-volume, low-latency routing (intent classification).
#   :standard    — heavier structured extraction.
#   :agent       — the tool-calling Slack agent loop (Ai::Agent::Runner). A more
#                  capable model since it drives multi-turn reasoning + tool use.
Rails.application.config.x.ai_models = {
  lightweight: ENV.fetch("AI_MODEL_LIGHTWEIGHT", "openai/gpt-4o-mini"),
  standard: ENV.fetch("AI_MODEL_STANDARD", "openai/gpt-4o"),
  agent: ENV.fetch("PINCER_AI_AGENT_MODEL", "anthropic/claude-sonnet-4.5")
}

# OpenRouter exposes far more slugs than RubyLLM's bundled registry knows about;
# assume declared models exist so arbitrary slugs don't raise ModelNotFoundError.
Rails.application.config.x.ai_assume_model_exists =
  ENV.fetch("AI_ASSUME_MODEL_EXISTS", "true") == "true"
