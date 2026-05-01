---
name: pr-author
description: Open a pull request on windsorcli/core. Enforces Conventional Commits title with module-scoped area, terse bullet changelog body, and a single workflow-required label. Use whenever creating a PR via gh pr create.
---

# Authoring a Windsor Core PR

You are opening a PR on `windsorcli/core`. Match the established repo style.

## Title format

`<type>(<area>): <short lowercase description>`

- **type**: `feat`, `fix`, `chore`, `refactor`, `docs`, `ci`, `security`
- **area**: module path or scope; slash-nested when the change is module-local
  - Examples: `aws`, `aws-eks`, `aws-vpc`, `cni/cilium`, `cluster/talos`, `kustomize/gateway`, `provider/incus`, `workstation`, `template`, `ci`, `deps`
- **description**:
  - 5–10 words
  - lowercase first word (recent convention; #1686, #1688, #1689, #1693)
  - imperative mood
  - no trailing period

Recent reference titles:
- `chore(aws): replace data-source discovery with module output chaining`
- `chore(aws-vpc): re-add enable_flow_logs as deprecated no-op`
- `chore(aws-eks): surface migration message when vpc_id/private_subnet_ids missing`
- `feat(cert-manager): update public issuer configurations for ACME and selfsigned certificates`

## Body format

Three to six bullets, one concrete change per line. Name the file, module, or behavior touched.

```
- <verb> <thing> in <where>
- <verb> <thing> in <where>
- <verb> <thing> in <where>
```

Rules:
- No headers, no "Summary"/"Test plan" sections.
- No "Why" preamble unless the change is genuinely non-obvious — then one short line at the top.
- No `Generated with Claude Code` footer; no `Co-Authored-By` trailer in the body (the commit trailer is fine).
- Plain informational sentences. No bold-headword bullets, no em-dashes, no quotable fragments. (Repo convention; see `feedback_voice_no_ai_punchiness` memory.)
- Do **not** imitate the multi-paragraph Claude-review or Cursor-Bugbot summaries that appear on most merged PRs — those are bot output, not the human-authored body.

## Required label

Exactly one label is required by `.github/workflows/enforce-pr-labels.yaml`. Pick from:

`feature, enhancement, documentation, fix, bugfix, bug, chore, dependencies, major, minor, patch`

Mapping from commit type:
- `feat` → `feature`
- `fix` → `bug`
- `chore` → `chore`
- `docs` → `documentation`
- dep bumps → `dependencies`
- `ci`, `refactor`, `security` → `chore` (unless the change is user-facing)

Set with `gh pr create --label <name>`.

## Command template

Use a HEREDOC for the body so newlines render correctly:

```bash
gh pr create \
  --title "<type>(<area>): <description>" \
  --label "<label>" \
  --base main \
  --body "$(cat <<'EOF'
- <bullet>
- <bullet>
- <bullet>
EOF
)"
```

For a stacked PR, set `--base <parent-branch>` and add a `Stack: N/M → #<parent-PR>` line at the bottom of the body so reviewers can navigate the chain.

## Before opening

1. Run `git status`, `git diff origin/main...HEAD`, and `git log origin/main..HEAD` to ground the bullets in actual changes — review every commit in the range, not just the latest.
2. Confirm the branch is pushed (`git push -u origin <branch>` if needed).
3. Pick the label that matches the dominant change type; if the diff spans types, pick the most user-visible one.
4. Show the user the proposed title, body, and label before running `gh pr create`. Adjust on feedback, then execute.

## Do not

- Do not push without the user's go-ahead.
- Do not amend or force-push to update the PR body — edit with `gh pr edit` instead.
- Do not add labels the workflow doesn't require (the enforcement only checks for *at least one* required label, but extras add noise).
