# VibeUE Self-Improvement — Gap Log

This directory is written by the `vibeue-self-improve` Claude Code skill. Every
time the agent hits a "no suitable tool" gap during a VibeUE task and runs the
pipeline, it appends a record to `gap-log.md`.

## Gap record format

Each record is one section appended to `gap-log.md`:

```text
## GAP-<YYYYMMDD>-<n>: <short title>
- **Date:** YYYY-MM-DD
- **Intent:** what the agent was trying to accomplish
- **Searched:** skills checked (manage_skills) + discover_python_* queries run
- **Why no tool:** why nothing existing fit the intent
- **Tier:** skill | cpp | unresolved
- **Artifact:** path to the skill/section or C++ method, or issue link
- **Verified:** the live-run evidence observed in the editor
- **Commit:** <sha> (on the fork)
```

`<n>` is a per-day counter starting at 1.

## Rules
- Records are append-only; never rewrite history.
- A record is only added after the resolution is verified live (or marked
  `unresolved` with an issue link).
- All commits referenced here are on the `fork` remote (`dry-eye/VibeUE`).
