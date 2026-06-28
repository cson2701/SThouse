---
name: github-issue-commit
description: Commit work for a GitHub issue in this repository. Use this skill when the user asks to commit changes, prepare commits for an issue, or group modified files into clean commits. Separate unrelated changes into distinct commits where necessary, and format every commit message as `[<issue-number>] <message>` with a concise subject of about 50 characters.
---

# GitHub Issue Commit

Use this workflow whenever the user wants changes committed for this repository.

## Required behavior

1. Identify the issue number for the work. If the user did not provide one and
it cannot be inferred safely from the current branch name, ask for it before
committing.
1. Review the working tree before staging anything:

```bash
git status --short
git diff --stat
```

Add targeted diffs as needed to understand how files relate.

1. Group changes by intent. If there are unrelated or loosely related changes,
create separate commits instead of one large commit.
1. Stage only the files that belong in the current commit.
1. Write each commit subject in this exact format:

```text
[<issue-number>] <commit message>
```

The subject after the issue number should be concise, around 50 characters, and
describe the grouped change clearly.

## Grouping rules

- Keep behavior changes separate from refactors when they are independently
  reviewable.
- Keep generated files separate when that improves review clarity.
- Do not mix unrelated fixes just because they are small.
- If all changes support one tight unit of work, one commit is acceptable.

## Safety rules

- Do not stage unrelated user changes.
- Do not rewrite history with `git commit --amend` unless the user explicitly
  asks for it.
- Do not use destructive git commands to force a clean tree.
- If grouping is ambiguous, explain the proposed commit split before committing.

## Commit workflow

Use normal non-interactive git commands. Prefer staging by explicit path. Check
the staged diff before each commit:

```bash
git diff --cached
git commit -m "[<issue-number>] <message>"
```

After committing, report the commit subjects you created and note any remaining
uncommitted changes.
