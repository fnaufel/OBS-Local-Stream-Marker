# Issue tracker: GitHub

Issues and specs for this repo live in GitHub Issues. Use `gh` from this repo so it resolves the GitHub remote.

## Operations

- Create: `gh issue create --title "..." --body-file <file>`.
- Read: `gh issue view <number> --comments`.
- List: `gh issue list --state open --json number,title,body,labels,comments`.
- Comment: `gh issue comment <number> --body-file <file>`.
- Label: `gh issue edit <number> --add-label "..."` or `--remove-label "..."`.
- Close: `gh issue close <number> --comment "..."`.

## Pull requests as a triage surface

**PRs as a request surface: no.**

## Skill language

"Publish to the issue tracker" means create a GitHub issue. "Fetch the relevant ticket" means read the GitHub issue and its comments.

## Wayfinding

A map is one issue labelled `wayfinder:map`; its tickets are child issues. Link children as GitHub sub-issues when available. Otherwise, list them in the map body and add `Part of #<map>` to each child. Use `wayfinder:<type>` for research, prototype, grilling, or task tickets. Record blocking relationships with GitHub issue dependencies when available, or with a `Blocked by: #<n>` line in the child issue. Claim a ticket by assigning it to the working developer. Resolve it by commenting with the answer, closing it, and adding a short decision and link to the map.
