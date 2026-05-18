# <Project Name> — Email Agent instruction file

> **Template.** Copy this file as `<slug>_agent.md` in this folder. Fill in every `TODO:` marker. Every gap corresponds to a `PH-###` row in the placeholders ledger.

## 1. Identity

- **Slug:** `<slug>` (must match `Email.Projects[].Slug` in `NuclearSystemChase\backend\appsettings.json`)
- **Project number / contract #:** TODO:
- **Owner / client:** TODO:
- **Site address:** TODO:
- **Architect (firm + lead contact):** TODO:
- **Superintendent on site:** TODO:
- **PM of record (who owns this project internally):** TODO:

## 2. Routing — what emails belong to this project

Matching is driven by the `Aliases` and `Keywords` arrays in `appsettings.json`. This file **documents** why those entries exist and catches near-misses. When any of the below appear in an email subject/body/sender without an overriding tell for another project, route to this project:

- **Unambiguous tells** (project name, #, address variants): TODO:
- **Owner / client names (people + firm):** TODO:
- **Architect names (firm + leads):** TODO:
- **Key sub firms** (spans trades; any of these in a sender or subject is usually this project): TODO:
- **Key sub contacts** (names that appear without firm): TODO:
- **Brand / franchise name** if applicable: TODO:
- **Anything else** (permit numbers, nicknames, internal codes): TODO:

Route **away from this project** when these appear (prevents false positives): TODO:

## 3. Naming conventions on this project

Document the file-naming patterns you see Chase + Derek + the team actually use, so the agent can find documents:

- **Pay applications:** TODO: (e.g., `FPK_24-088_PayApp_04.pdf`)
- **RFIs:** TODO:
- **Submittals:** TODO:
- **COs:** TODO:
- **Daily reports:** TODO:
- **Meeting minutes:** TODO:
- **Drawings / revisions:** TODO:

## 4. Related SharePoint paths — "when asked X, check here"

Maps common ask-patterns to the folder/file the answer usually lives in. Example row format: `"what's the latest pay app status" → <path>`

| Ask pattern | First place to look | Second place |
|---|---|---|
| TODO: | TODO: | TODO: |
| TODO: | TODO: | TODO: |

## 5. Expected output format

When the agent answers a question about this project, follow this shape unless Chase asks for a different one:

1. **Direct answer** (1-2 sentences).
2. **Source** — file path + date OR email sender + date.
3. **Confidence** — `confirmed` / `derived` / `guess`. Never dress up a guess as confirmed.
4. **Related** — 1-3 adjacent items Chase may want next.
5. **Open question back to Chase** — if the answer needs his input.

## 6. Known answered questions (curated by Chase over time)

Short rows so "did we already answer this?" is a lookup, not a vibe. Grow this list as questions get answered — the answered-question hash index (Phase 1b) will augment this, but a human-curated list beats the index for the top-of-mind asks.

| Question pattern | Answer + source | Last confirmed |
|---|---|---|
| TODO: | TODO: | TODO: |

## 7. Known blockers / hot issues (as of last update)

TODO: Keep this short — top 3-5 items. Delete/move to answered when resolved.

## 8. Project-specific rules for the agent

Anything non-obvious about HOW to handle this project's emails that isn't covered by the global PM duties doc. Examples of the kind of thing that goes here:
- "Pay apps on this job must reconcile to KW's G703 before being considered final."
- "Owner wants every RFI CC'd to <name> by close of business the day it's raised."
- TODO:

---

**Ledger reference:** placeholder rows in `C:\Users\ChaseLandry\.claude\projects\C--Users-ChaseLandry\memory\placeholders_ledger.md`. Grep for this project's slug or `PH-###`.
