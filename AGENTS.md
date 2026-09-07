# Nightwatch Array Project Instructions

## Working Style

Adapted from [OpenAI's GPT-6 Astra prompting guidance](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-6-astra#prompting-best-practices), reviewed 2026-09-07.

- Finish action requests within their scope. Infer routine details, retain prior
  approvals, and incorporate corrections without losing the original task.
- Ask for missing decisions affecting scope, design, or irreversible actions.
  Prepare authorized work first; continue independent work while awaiting answers.
- Explicit user instructions override skill guidelines. If a file blocks work,
  link it, quote the rule, and distinguish the requirement from your interpretation.
- Lead with the result in concise, plain prose. Use lists where useful; report
  verification and material limitations.
- Autonomously use subagents for independent work when this is expected to save
  time or improve quality. Start with 1-2; add more only when independent work
  justifies the coordination and usage cost.
- Explicitly select both model and reasoning effort for every subagent,
  including reviewers: `gpt-5.6-luna` / `max` for clear, bounded work or
  `gpt-5.6-terra` / `xhigh` for broader implementation and investigation. Choose
  directly by task; a Luna attempt is not required before using Terra.
- Use `gpt-5.6-sol` / `xhigh` only when genuinely needed, either from the outset
  or after evidence that Luna/Terra cannot resolve the task. Pass along failed
  approaches and remaining questions to avoid repeating the same work.
- Never use GPT-6 Astra as a subagent, including for review. The primary agent
  keeps context-dependent decisions, difficult judgement, and final integration.
  If the selected model/effort is unavailable, handle the work directly and
  report the limitation instead of silently inheriting Astra or substituting.
- Give each agent a concrete goal, relevant context, owned files or a read-only
  remit, and completion criteria. Use fresh context by default
  (`fork_turns: "none"` where supported), with necessary instructions and evidence rather
  than the full conversation. Prefer independent regression, save
  compatibility, and documentation checks; parallelize implementation when file
  ownership is separate. Avoid overlapping edits.
- Keep simple edits and CodeGraph exploration local and avoid duplicate work.
  Continue useful independent work while agents run. The primary agent reviews
  results against the actual changes and owns integration and final validation.
  Use readable handoffs; delegation does not expand approved design scope or
  waive the completion requirements below.
- Complete required checks; repeat or broaden them only for changes, failures,
  or unresolved concerns. Add tests for meaningful behavior, avoiding duplication
  of implementation details.

These defaults supplement the project contracts below. In particular, routine
implementation choices do not need a design meeting, but a conflict with
`docs/design.md` still follows Orientation. Test calibration does not waive the
Windows export or commit requirements. Agent Room turn boundaries apply only
while participating in a room meeting.

## Orientation

Read the README and design brief before changing anything. Then read only the
relevant sections of the detailed references; historical records are for tracing
a specific decision, not a routine prerequisite.

- [README.md](README.md) — how to run, test, export, and where the Godot binary
  actually lives. The commands this file requires are written out there.
- [docs/design.md](docs/design.md) — core direction, current progression, open
  decisions, and the boundary between autonomous adjustments and user decisions.
  Within the requested task, small UI, presentation, and balance adjustments are
  authorized; report their effect and validation, and update the relevant detail.
  Ask before changing core direction, controls, save compatibility, content
  direction, the overall economy, or the ending. Preserve the user's decision
  before or alongside implementation. Never rewrite a guardrail to justify an
  unauthorized change.
- [docs/design-details.md](docs/design-details.md) — current values and behavior;
  consult only the feature being changed. These values are starting points within
  the design brief's adjustment boundary, not blanket approval gates.
- [docs/systems.md](docs/systems.md) — scene tree, signal wiring, ownership.
- [docs/probes.md](docs/probes.md) — what each test and probe measures.
- [docs/legacy-contracts.md](docs/legacy-contracts.md) — retained compatibility
  and diagnostic paths; read when touching those paths, not as future content requirements.

## Completion Requirements

- After making project changes, always run the relevant tests and build or refresh the Windows `.exe` before reporting the task as complete.
- If the executable export fails, do not report the task as complete. Report the failure and its cause.
- Include the absolute path to the generated `.exe` in the final response.
- Commit the work before reporting it complete. Finished work is not left
  sitting in the working tree.
- Leave no new file untracked at the end of a unit of work. An untracked file
  has no ancestor commit, so a later branch that creates the same path cannot be
  three-way merged; the merge degenerates into choosing one whole file over the
  other instead of combining them.
- Stage only the files belonging to your own unit of work. Another session may
  be editing this tree at the same time. Never sweep its changes into your
  commit, and split unrelated work into separate commits.
- If work is paused rather than finished, commit it anyway. A checkpoint commit
  gives later branches an ancestor; a dirty tree gives them nothing.

## Commit Attribution

Keep the human author as `Frotrue <105928069+frotrue@users.noreply.github.com>`.
Preserve the repository's matching Git user identity; never replace the author
or the human committer identity with an AI name.

End each AI-assisted commit message with the co-author trailer for the agent
that performed the work, separated from the body by a blank line:

- Claude models / Claude Code: `Co-authored-by: Claude <noreply@anthropic.com>`
- OpenAI models / Codex: `Co-authored-by: Codex <noreply@openai.com>`

Choose by the actual contributing agent, not by a fixed project-wide default.
Model variants and reasoning levels use their agent's shared name above.
Include each contributing agent at most once; include both only when both
contributed to the committed work. Never invent a GitHub account or numeric
noreply address to force a profile association.

Apply the same attribution rules to merge and squash commit messages. Do not
rewrite existing published commits just to change attribution unless the user
explicitly requests a history rewrite.

## Agent Room Protocol

When work is being run through an Agent Room meeting, the room is the
primary channel. A turn in the user's chat is not the unit of work; the
meeting is.

### When an agent may end its chat turn

End the turn only when one of these is true:

- The next step requires a decision only the user can make — merge, scope, or
  design direction.
- The other agent is holding and nothing is pending from either side.
- The user has interrupted with something else.

### When an agent may not end its chat turn

- Immediately after posting a work order, a question, or a review. The other
  agent will answer in minutes, and a turn that ends here leaves that answer
  unread until the user manually asks for it.
- On a `listen` timeout that returned no messages. A timeout means nothing has
  arrived yet, not that the meeting is over. Call `listen` again.
- Merely to report progress. Progress reporting is batched into the decision
  points above.

### When ending mid-meeting

Say what is outstanding and who is expected to speak next, so the user knows
whether more is coming or the room is genuinely idle.

### Practical

- Prefer long waits (240–300s) over short ones; each round trip costs the user
  a turn.
- Never run two simultaneous waits for the same agent.
- Verify the other agent's reported results independently — re-run the tests
  and read the diff rather than accepting the report. This has caught a flaky
  suite, a measurement that counted the wrong thing, and descriptions that did
  not match behaviour.
