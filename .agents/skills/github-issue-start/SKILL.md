---
name: github-issue-start
description: Start work on a GitHub issue in this repository. Use this skill when the user asks to begin a GitHub issue, work from an issue number, or prepare a fix/feature from a GitHub issue. Always create or switch to the issue branch with `./scripts/create_branch.sh <issue_number>`, analyze the issue, present a concrete plan, and wait for explicit user approval before implementing the plan.
---

# GitHub Issue Start

Use this workflow whenever the user wants to start a GitHub issue for this
repository.

## Required behavior

1. Identify the issue number. If the user did not provide one, ask for it.
1. Run the repository helper exactly as provided:

```bash
./scripts/create_branch.sh <issue_number>
```

Do not replace this with a manual branch naming flow unless the script is
missing or broken.

1. Read the issue details with `gh issue view`, including at minimum the title,
body, and labels. Read comments too when they affect scope or acceptance
criteria.
1. Inspect the relevant project files before proposing a plan.
1. Give the user a concise implementation plan tailored to the issue and the
current codebase.
1. Stop after the plan and explicitly ask for approval before making any code
changes, running implementation commands, or editing files.

## Issue analysis workflow

Use this sequence:

```bash
gh issue view <issue_number> --json title,body,labels,assignees
gh issue view <issue_number> --comments
```

Then inspect the codebase paths that are most likely involved. Prefer `rg` for
search and read only the files needed to understand the change.

## Planning requirements

The plan should:

- state the likely files or subsystems involved
- call out any assumptions or missing acceptance criteria
- identify validation you expect to run
- remain implementation-ready but not execute anything yet

If the issue is ambiguous, include the ambiguity in the plan and ask the user to
confirm before implementation.

## Hard stop before implementation

After presenting the plan, ask for confirmation in plain language, for example:

`Approve this plan and I'll implement it.`

Do not start coding until the user explicitly approves.
