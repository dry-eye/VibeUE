# VibeUE Gap Log

Append-only. Format defined in `README.md`.

---

<!-- Example record (template — not a real gap). Real records appended below. -->
## GAP-00000000-0: (example) set actor folder path
- **Date:** 0000-00-00
- **Intent:** Move a spawned actor into a named outliner folder.
- **Searched:** manage_skills(list) → level-actors skill loaded, no folder method; discover_python_function(ActorService, "folder") → none.
- **Why no tool:** Neither the skill nor ActorService exposed folder assignment.
- **Tier:** skill
- **Artifact:** Content/Skills/level-actors/SKILL.md (added "Outliner folders" gotcha)
- **Verified:** Ran recipe live; actor appeared under folder "Test" in the outliner.
- **Commit:** 0000000

---
