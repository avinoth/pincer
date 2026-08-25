# Architecture

How the Pincer agent is put together — the turn lifecycle, the human-in-the-loop
pause/resume contract, the tool registry, and the scheduled notification chains.
For the product-level overview and setup, see the [README](README.md).

## The agent, in one paragraph

Pincer is a [`ruby_llm`](https://github.com/crmne/ruby_llm) agent (over OpenRouter)
that lives in Slack threads. The entry point is `Ai::Agent::Runner`, which runs
**one turn per call**; tools live in `app/ai/agent/tools/`. A turn runs inside a
GoodJob background job so Slack gets its fast ack, and a turn can pause partway to
let a human act in Slack, then resume exactly where it left off.

## Core pieces

- **`Runner`** (`app/ai/agent/runner.rb`) runs one turn against an already-`running`
  `AgentRun`: it replays the persisted transcript into a `RubyLLM::Chat`, hands it
  every registered tool, and drives RubyLLM's built-in tool loop, persisting each
  assistant message and tool result as it happens. A turn ends in one of three
  states: `completed`, `paused_on_tool`, or `failed`.
  - **Streaming.** Slack only allows Block Kit blocks in `chat.stopStream`, never
    `appendStream`, so a tool's card can't be inlined mid-message. The Runner
    therefore streams **one Slack message per model completion**, not one per turn.
    A long-lived decorator streamer handles thread-level status (`assistant.threads.setStatus`
    — the "is thinking…" / per-tool status line); the current text segment is a
    separate streamer, opened lazily on the first text chunk and finalized right
    before the next tool call. The result is a guaranteed ordering of
    `[text] → [tool card] → [text]`.
- **`Tools`** (`app/ai/agent/tools.rb`) is a registry + factory. A tool registers
  itself simply by subclassing `Tools::Base` (via `Base.inherited`) — no manual
  wiring. `build_all(context)` returns one fresh instance of every tool per turn.
- **`Tools::Base`** (`app/ai/agent/tools/base.rb`) — every tool's `#execute(**kwargs)`
  receives a `ToolContext` and must **return a Hash**, either the result or
  `{ error: "..." }`. **Tools must never raise** — they rescue internally. A tool
  signals "I've handed off to a human" by returning the `Tools::PENDING` sentinel,
  which `#call` translates into a `RubyLLM::Tool::Halt` so the loop stops cleanly
  instead of auto-continuing to the model.
- **`ToolContext`** (`app/ai/agent/tool_context.rb`) — the struct every tool is built
  with: `conversation`, `organization`, `user` (this turn's author), `agent_run`.
- **`SystemPrompt`** (`app/ai/agent/system_prompt.rb`) — builds the per-turn system
  instructions: persona, date/timezone, memory sections, and one guidance section per
  major capability.
- **`Resume`** (`app/ai/agent/resume.rb`) — re-enters the `Runner` for a paused run
  after a human acts in Slack (see below).

## The PENDING → pause → resume flow

Some tools can't finish synchronously — they need a human to click something in Slack
(a form, a dropdown, a confirm button). The pattern:

1. The tool stashes what it needs to resume onto `agent_run.pending_tool_call["args"]`
   (**merge, don't overwrite** — the runner writes sibling `"id"`/`"name"` keys onto the
   same hash).
2. It posts an interactive Slack message whose value/block_id carries the `agent_run.id`,
   then returns `Tools::PENDING`.
3. `Runner#on_tool_result` sees the `Halt(PENDING)`, sets the run to `paused_on_tool`,
   and records `pending_tool_call["id"]`/`["name"]`.
4. A Slack interaction handler (`app/api_clients/slack/interactions/*`, wired in
   `router.rb`) fires when the human acts. Org-scoping its lookup of the `AgentRun`, it
   either:
   - **still paused on this exact tool** → enqueues `AgentResumeJob`. `Ai::Agent::Resume`
     appends the human's result as a `role: :tool` message keyed to the pending call's
     `id`, flips the run back to `running`, and re-runs `Runner` — the model sees the
     result exactly as if the tool had returned it inline.
   - **moved on** (a run holds only *one* outstanding pause; a new message supersedes it)
     → instead of resuming a stale pause, it enqueues a fresh `AgentTurnJob` with a
     narrated `event:` string so the outcome still reaches the thread.
5. **Idempotency.** Slack retries interactions and two people can race the same
   button/dropdown, so handlers stamp something like `pending_tool_call["produced_goal_id"]`
   once the action has taken effect and short-circuit on replay.

The canonical instance is `show_goal_create_form` → `AgentOpenCreateGoalModal` →
`CreateGoalSubmission`; a simpler one (no modal, just a `static_select`) is
`pick_goal` → `AgentPickGoalSelection`.

## Tools

| Tool | Pauses? | What it does |
|---|---|---|
| `list_goals` | no | Compact, filterable summaries of the org's goals. |
| `get_goal` | no | Full detail on one goal by id. |
| `show_goal_create_form` | yes | Posts a "Create Goal" button opening the real modal; the submission creates the goal. |
| `edit_goal` | no | Direct-mutates a goal's scalar fields via `UpdateGoal`, then re-posts the card. Gated on `Goal#modifiable_by?`. |
| `pick_goal` | sometimes | Fuzzy title search to resolve an ambiguous goal reference. 0 → error; 1 → inline; 2–25 → pauses with a dropdown; >25 → asks to narrow. |
| `create_initiative` | no | Direct-creates an initiative via `CreateInitiative` when goal/owner/title are known. Refuses a goal in a terminal state. |
| `show_initiative_create_form` | yes | Fallback for `create_initiative` when those aren't all known: posts a button opening the modal. |
| `pick_initiative` | sometimes | Fuzzy initiative search (optionally scoped to a goal); same 0/1/2–25/>25 shape as `pick_goal`. |
| `edit_initiative` | no | Direct-mutates title/description/owner/status via `UpdateInitiative`. Parent goal is never reassigned. |
| `delete_initiative` | yes (confirm-first) | Posts a danger confirm button and pauses; only deletes once clicked. |
| `save_memory` / `forget_memory` | no | Persist / retract a durable org- or user-scoped fact. |
| `record_metric_update` | no | Reports a new metric value via `RecordMetricUpdate`: `MetricUpdate` + advances `Metric#current_value` + logs a `GoalUpdate`. |
| `update_initiative_status` | no | Changes an initiative's status via `UpdateInitiativeStatus`, logging a `GoalUpdate`. |
| `add_goal_update` | no | Logs a free-text `GoalUpdate(kind: note)`, optionally scoped to an initiative. |
| `complete_checkin` | no | Flips the user's open `Checkin` rows to `completed`. Called last, after the capture tools. |

Every mutating path — agent tool, Block Kit button, or modal — funnels through the
same interactor and the same `#modifiable_by?` authorization check on the model, so
there's exactly one place each rule lives.

## Scheduled chains (no agent, no chat)

These are pure GoodJob cron + interactors, each idempotent via a partial unique index
and each guarded by a `good_job_control_concurrency_with` key so an overlapping tick
can't double-post.

- **Weekly check-in nudge → capture.** `CheckinNudgeSchedulerJob` (every 15 min) finds
  each `(subject, owner)` due its "one day before the weekly summary" nudge and upserts a
  `Checkin`. `SendCheckinNudgeJob` DMs each owner one clubbed card and pre-creates the
  `Conversation`, so the reply has context before the agent runs. The reply lands through
  the normal `Slack::EventsController` → `AgentTurnJob` DM path, where three focused
  capture tools (`record_metric_update`, `update_initiative_status`, `add_goal_update`)
  each call a thin interactor; `complete_checkin` closes the loop.
- **Goal summaries.** `GoalSummarySchedulerJob` (every 15 min) finds in-progress published
  goals due their weekly summary right now (org-local `summary_day`/`summary_time`),
  expires the week's stale check-ins, then runs `GenerateGoalSummary` — a one-shot
  `RubyLLM::Chat#with_schema` structured-output completion (no tools, no conversation) —
  and posts the summary card.
- **Lifecycle notices.** `GoalLifecycleSchedulerJob` (every 15 min) is the only thing that
  drives `Goal#status` on a schedule: flips `not_started → in_progress` on the start date
  (with a lightweight, no-LLM start notice) and, on the end date, decides
  `completed` vs `ended` via `GoalLifecycle.outcome_for`, then runs `GenerateGoalSummary`
  over the goal's entire cycle for a closing summary.

All channel-posting chains key their due/window math off **`Organization#time_zone`**
(a channel has no single recipient to localize against), unlike the check-in nudge which
localizes per owner.

## Adding a tool

1. Drop a file in `app/ai/agent/tools/`, subclassing `Base` — that's the whole
   registration step.
2. Update the explicit registry assertion in `spec/ai/agent/tools_spec.rb`.
3. Add a tool spec covering the happy path, org-scoping (a foreign-org id is "not found",
   not a leak), and the rescue-not-raise contract (`{ error: ... }`, never an exception).
4. If it pauses for a human, add a Slack interaction handler under
   `app/api_clients/slack/interactions/`, register the `action_id`/`callback_id` in
   `router.rb`, and spec the handler.
5. If the model needs steering beyond the tool's own `description`, add a guidance
   section in `system_prompt.rb`.

---

## Domain glossary

The ubiquitous language for Pincer — the terms as the team and the agent use them.

- **Goal** — an outcome the company or a team commits to. Has a time range, one or more
  owners, and usually a metric it's judged by. Goals can roll up under a parent goal or
  stand alone.
- **Initiative** — the work a team believes will move a goal. Owner-assigned by the goal's
  team, not handed down. Carries a status but no metric or time range of its own; the
  intended integration point for external trackers (Jira, Linear).
- **Metric** — the measurable signal a goal is judged by: a name, a direction (increase or
  decrease), a baseline, a target, and a unit. A goal has one primary metric.
- **Quarter** — an organizational convention (Jan/Apr/Jul/Oct starts) unless the org's own
  memory says otherwise.
- **Conversation** — one Slack thread's ongoing exchange with the agent: the durable
  transcript humans and agent share.
- **Turn** — one round of the exchange: a triggering message/event, the agent's reasoning
  and tool use, and its reply.
- **Run** — the execution of a single turn. It can pause when the agent hands control to a
  human, then resume or be superseded once they act or the conversation moves on.
- **Tool** — a discrete capability the agent can invoke; the agent narrates what happened
  back to the human.
- **Organization Memory** — durable facts about how the org operates, visible across every
  member's conversations ("quarters start in February").
- **User Memory** — durable facts about one person, visible only in their own conversations
  ("prefers terse replies"). The default scope for facts learned in a private conversation.
- **Draft** — two senses: a *pre-creation draft* is the agent's best-guess values shown in
  the goal form before anything exists; a *draft goal* is one already created but not yet
  published. Publishing status is orthogonal to progress — a draft goal can still be tracked.
- **Surface** — where a conversation happens: the assistant split-view, a channel thread, or
  a DM. Same agent, same rules everywhere; only the Slack UI differs.
