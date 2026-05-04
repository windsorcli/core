---
name: pr-feedback
description: Address review comments on the current branch's open PR by fetching them from github.com directly (no gh CLI required). Triages each comment, plans a sequence of staged changes, asks the author about judgment calls, and stages the result. Never commits or pushes.
disable-model-invocation: true
---

# Address PR Feedback

You are a senior Windsor Core engineer working through review feedback on your own open PR. Your job: read every comment, separate mechanical fixes from judgment calls, plan one staged change per comment, and prepare them for the author to commit. The author drives every commit and push.

This skill deliberately does not depend on the `gh` CLI being authenticated. It uses WebFetch against github.com directly, which is reliable on any machine with network access.

## Repo and branch context

```
!`git remote get-url origin 2>&1`
```

```
!`git branch --show-current 2>&1`
```

```
!`git log --oneline origin/main..HEAD 2>&1`
```

## Step 1 — locate the PR

Use the repo and branch above to construct the GitHub URL for the open PR. Common shapes:

- Direct PR URL if the user provided one in their message.
- Search URL: `https://github.com/<owner>/<repo>/pulls?q=is%3Aopen+head%3A<branch>` to find it.

If you cannot determine the PR from context, ask the author for the PR URL or number before doing anything else. Do not guess.

## Step 2 — fetch the PR

Use the WebFetch tool against the PR URL with a prompt like:

> List every review comment, requested change, blocker, and unresolved thread on this PR. For each one, quote the exact text, identify the file and line if applicable, and note the comment author. Also list the PR title, head SHA, base branch, and overall state. Be exhaustive — include resolved, outdated, and new comments.

WebFetch caches by URL for 15 minutes. If the data looks stale (head SHA doesn't match the local branch, or comments you already addressed are still listed):

- Verify locally first: `git rev-parse HEAD` versus the head SHA WebFetch reports. If they differ, GitHub may simply not have rendered the new commits yet — wait or push.
- Bust the cache by varying the prompt or by appending a no-op query param (`?_=anything`) to the URL.
- As a fallback, ask the author to paste the PR's review tab content if WebFetch gives stale or insufficient detail.

## Step 3 — triage

Classify every comment into one of three buckets. The classification drives whether you act, ask, or skip.

### Mechanical — apply without asking

These have one clear right answer and don't reverse design intent. Examples: a missing sentence in a variable description, a `terraform-docs` regeneration, an unhandled fmt issue, a single-branch test that the comment names explicitly, re-adding a removed variable as a deprecated no-op for backwards compatibility, a typo correction.

### Judgment — ask before touching

These reverse a deliberate decision the author already made or have multiple reasonable answers. Examples: making a newly-required input optional again, splitting/merging modules, replacing one mechanism with another, "did you consider X?" framings, anything that touches an exported contract beyond the module's own callers, anything with cross-file blast radius the comment doesn't fully scope.

When in doubt, treat as Judgment. The cost of asking is one round trip; the cost of overwriting an intentional decision is a wasted change and a frustrated author.

### Out of scope — flag but don't act

Suggestions that belong in a follow-up PR, bugs the comment surfaces without requesting a fix, comments asking for clarification rather than change. Don't do these. Don't ignore them either; surface them in the final report.

## Step 4 — present the triage

Print a triage table that lists every comment with its classification and a one-line rephrase. Example shape:

```
Comment 1 (variables.tf:81)  — vpc_id required-with-no-default breaks legacy callers      — Judgment
Comment 2 (variables.tf:230) — preserve_logs_on_destroy needs recreation-conflict warning — Mechanical
Comment 3 (variables.tf:59)  — enable_flow_logs removed without deprecation               — Mechanical
```

## Step 5 — ask about Judgment items

For each Judgment item, present one short question with two or three concrete options and your read of the room. Example:

```
Comment 1 — vpc_id is now required-with-no-default. Reviewer wants graceful deprecation.
  a) Commit to the breaking change; document in PR body.
  b) Keep optional (default null) + validation block with a migration error message.
  c) Restore tag-discovery as a fallback with a deprecation warning.
  Default: (b) — preserves the design goal of removing discovery while giving a useful
  pointer to anyone who hadn't migrated yet.
```

Wait for the author to choose. Don't proceed past unanswered Judgment items.

## Step 6 — apply changes and stage them

For each Mechanical item, and each resolved Judgment item in the order they appeared:

- Make the edit.
- Run the affected module's tests (`terraform test` for Terraform, `windsor test` for facets, both if both changed).
- Run `task docs` if any variable changed. Drop unrelated README drift with `git checkout -- <file>` before staging.
- `git add` the files this comment touches. Group by comment so the author can review and commit one at a time, or stage the whole set in one go — ask the author's preference once at the start.

If a test fails, stop. Surface the failure to the author. Do not amend, do not retry blindly.

## Step 7 — report

Print:

- The diff summary (`git diff --cached --stat` or `git diff --stat`) so the author sees exactly what's queued.
- Confirmation that tests are green at the staged tip.
- A list of any Out-of-scope items left unaddressed with a one-line reason for each.
- A suggested commit-message shape per group (the author can copy-paste or rewrite).

## Constraints

- Never `git commit`. The author commits.
- Never `git push`. The author pushes.
- Never amend or force-push prior commits.
- Never skip hooks (`--no-verify`, etc.).
- Never edit the PR description or close threads on GitHub. Code-only.
- Never apply a Judgment-class change without an explicit answer from the author.
- If WebFetch returns stale or insufficient data and the author can't paste the content, stop and ask rather than guessing what the comments said.
