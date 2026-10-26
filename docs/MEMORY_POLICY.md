# Project memory policy

These Markdown files are the durable project memory for QuietSpeech. They describe current truths and important reasons; GitHub Issues and PRs track work in progress.

## Before and after work

1. Read [brief.md](brief.md), then the files relevant to the task. Check code, site, tests, and recent decisions when a claim needs verification.
2. Before finishing, inspect what changed and ask whether any current fact in this directory is now stale.
3. Update affected memory files in the same branch or PR as the work. If no durable fact changed, say so in the final report or PR description.
4. Cite the supporting code path, issue, PR, measurement, or customer note for a new claim. Mark unverified information as a hypothesis or open question.

## File ownership

| Change | Review and update |
| --- | --- |
| One-sentence description, stage, top priorities, or navigation | `brief.md` |
| Shipped workflow, feature status, requirement, privacy behavior, pricing mechanics, or limitation | `product.md` |
| Target customer, pain point, alternative, or positioning evidence | `audience.md` |
| Published message, campaign, channel, experiment, or measured learning | `marketing.md` |
| Durable choice with rationale or a choice being superseded | `decisions.md` |

## Rules for trustworthy memory

- Use **Implemented**, **Published**, **Planned**, **Hypothesis**, and **Unknown** precisely. A merged implementation is not proof that a public service is working.
- Keep a fact in one detailed file and summarize it elsewhere with a link. Avoid conflicting copies.
- Update a file’s review date only after checking its contents, not just because a related file changed.
- Do not store secrets, private customer data, raw transcripts, or unapproved customer quotes in Git.
- For a bug fix that restores already documented behavior, a memory edit may be unnecessary. Explain that choice when reporting the work.
- When sources disagree, report the conflict and resolve it with the owner or an authoritative source before changing an external claim.
- Keep ongoing run logs, issue status, and PR status out of these files.
