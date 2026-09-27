# Working on Issues

How work is tracked and picked up in this repository. Consumer requests follow [consumers](consumers.md) first; this page covers delivery work.

## Structure

- One roll-up Issue per release (for example "swift-mcp-host 0.1") holds the delivery Issues as sub-issues. The maintainer owns the roll-up and closes it when every sub-issue is closed and its Done-when holds.
- Each delivery Issue is independently useful: it states its outcome, scope, non-goals, Done-when, authority (the requirement sections it implements) and proof (the [validation](validation.md) layer that proves it).
- Dependencies use GitHub's "blocked by" relationship. It is set only when meaningful work cannot start without the other Issue. Related work is linked in the Issue text, not as a blocker.

## Labels

| Label | Meaning |
|---|---|
| `ready` | No open blockers; anyone can pick it up |
| `blocked` | Has an open blocker; remove when the blocker closes and add `ready` |
| `owner-action` | Needs the owner: credentials, their devices or an interactive approval |
| `consumer-request`, `accepted`, `needs-decision`, `consumer-owned` | Consumer intake; see [consumers](consumers.md) |

## Picking up an Issue

1. Choose a `ready` Issue and assign yourself. One assignee per Issue.
2. Read its authority sections in [requirements](requirements.md) and [architecture](architecture.md). If the Issue and the requirements disagree, the requirements win; comment on the Issue and stop until it is corrected.
3. If you find an owner decision the documents do not settle, record it in [decisions](decisions.md) under "Owner decisions", comment on the Issue, and do not settle it yourself.
4. Work on a branch named `issue-<number>-<short-name>`.

## Pull requests

- One Issue per pull request, with `Fixes #<number>` in the description.
- The pull request shows each Done-when item and where it is proven.
- Behavior changes update their owning document in the same pull request.
- CI must pass. Do not weaken or delete a test to make it pass; if a test is wrong, say why in the pull request.
- The maintainer reviews and merges.

## After merge

Close the Issue through the pull request, then relabel any Issue it was blocking from `blocked` to `ready` when it has no other open blockers.
