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
- Default to working directly in the primary GPT-6 Astra session. Keep planning,
  implementation, review, testing, and final integration with this single agent.
- Spawn subagents only when the user explicitly requests subagents, delegation,
  or parallel agent work. Task size, expected cost savings, and review needs do
  not authorize delegation. Do not routinely ask to delegate; proceed directly.
- When delegation is explicitly requested, keep it within the requested scope.
  Give each agent a bounded outcome, relevant context, clear file ownership or
  a read-only remit, and completion evidence. The primary agent verifies results
  and owns integration and final validation. Avoid duplicate work, overlapping
  edits, and nested delegation beyond the user's request.
- After required orientation, start with the supplied files and evidence.
  Expand into historical documents, old commits, or repository-wide searches
  only to resolve missing or conflicting information. Read focused sections;
  avoid repeated whole-file reads and unnecessarily large tool outputs.

### Verification efficiency

- Batch independent searches and reads with focused output; inspect every result.
  Keep dependent edits/checks sequential and review the completed diff without
  repeatedly rereading it. Expand only to resolve a specific gap.
- For reversible, low-impact copy/style/docs/config edits, use diff review and
  useful existing or visual checks. Add tests for meaningful behavior and concrete
  risks, not copied formulas or tunable style values. Do not create test
  infrastructure merely for a small edit. Required repository gates still apply.
- Skip checks covered by a planned aggregate unless an earlier result is needed.
  Reuse passes only when relevant inputs are unchanged, preserving required
  independent verification. After failure, fix the cause and rerun affected checks
  first; broaden only for integration needs or a specific unresolved concern.
  Stop when selected checks and required gates pass.
- Do not change unrelated product code or weaken assertions for an environment
  or fixture failure. Establish the contract or environment difference; workers
  return scope or acceptance changes to the primary agent.

### Explicit execution-only assignments

These rules apply only to command execution explicitly delegated by the user.

- Supply cwd, commands, prerequisites, completion evidence, and time limits.
  The runner executes and reports; it does not edit source, change acceptance
  criteria, commit/push, clean/reset/checkout, or spawn more agents.
- Give each job one execution and monitoring owner. Preserve handles, logs, and
  exit status; resume existing jobs. Report actual PASS, FAIL, BLOCKED, or TIMEOUT
  with decisive evidence. Phase progress and stale artifacts are not completion.
- Report blockers promptly. The primary agent handles diagnosis, scope changes,
  independent verification, and final completion requirements.

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
- [docs/scene-authoring.md](docs/scene-authoring.md) — use for UI/object authoring;
  stable scene/resource structure, project drawing exceptions, and behavior-preserving migration.
- [docs/probes.md](docs/probes.md) — what each test and probe measures.
- [docs/legacy-contracts.md](docs/legacy-contracts.md) — retained compatibility
  and diagnostic paths; read when touching those paths, not as future content requirements.

## Constellation Authoring

- Before adding a constellation or changing its stars/geometry, follow
  [docs/constellation-geometry.md](docs/constellation-geometry.md).
- Establish a real reference figure and catalogue identities first. Match its
  star count and relative positions; do not invent, omit, duplicate, mirror or
  stretch stars to fit a desired research count. Document any user-approved
  simplification explicitly, including shared stars and non-star markers.
- Verify catalogue coordinates and counts, then capture the running game and
  compare every affected figure side by side with the reference chart/photo.
  Check connections, clipping, overlap and selection as well as shape. Record
  sources, count reconciliation, screenshots and remaining differences before
  reporting completion. Generated coordinates alone are not visual validation.

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
