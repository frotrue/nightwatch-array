# Nightwatch Array Project Instructions

## Orientation

Read before changing anything:

- [README.md](README.md) — how to run, test, export, and where the Godot binary
  actually lives. The commands this file requires are written out there.
- [docs/design.md](docs/design.md) — genre, target length, the three-layer
  structure, and the principles a change has to satisfy. If a proposal
  conflicts with this document, raise the conflict with the user and get a
  decision. Record the approved decision in the document before or alongside
  the code. Never edit the design document on your own authority to make a
  change you already want to look compliant.
- [docs/systems.md](docs/systems.md) — scene tree, signal wiring, ownership.
- [docs/probes.md](docs/probes.md) — what each test and probe measures.

## Completion Requirements

- After making project changes, always run the relevant tests and build or refresh the Windows `.exe` before reporting the task as complete.
- If the executable export fails, do not report the task as complete. Report the failure and its cause.
- Include the absolute path to the generated `.exe` in the final response.

## Commit Attribution

Every commit created for this project must end with this co-author trailer,
separated from the commit message body by a blank line:

```text
Co-authored-by: Claude <81847+claude@users.noreply.github.com>
```

That is the GitHub noreply address for the `claude` account, so the commit
resolves to that profile instead of showing an unlinked name. The address
must keep its numeric id prefix; the bare `name@users.noreply.github.com`
form does not resolve for accounts created recently.

Use this trailer and no other, whatever attribution an agent is otherwise
configured to add. Exactly one co-author line per commit.

## Agent Room Protocol

When work is being run through an Agent Room meeting, the room is the
primary channel. A turn in the user's chat is not the unit of work; the
meeting is.

### When an agent may end its chat turn

End the turn only when one of these is true:

- The next step requires a decision only the user can make — commit, merge,
  scope, or design direction.
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
