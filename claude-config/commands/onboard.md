First-run health check for Chase Cowork. Please verify my install is working properly by running the following checks using the Microsoft 365 MCP tools. For each check, output a single line with `[OK]`, `[WARN]`, or `[FAIL]` plus a brief detail. At the end, summarize and tell me what (if anything) to message Chase about.

Be concise — this is a status check, not a tutorial.

---

## Checks to run

**1. Microsoft 365 sign-in.** Fetch the signed-in user's profile via MS Graph (whoami / me endpoint). Confirm:
- The email ends in `@chasegroupcc.com`
- Display name is populated

Output: `[OK] Signed in as <Display Name> <email>` or `[FAIL] not signed in — sign in with your @chasegroupcc.com account`.

**2. Mailbox access.** Search the user's inbox for messages received in the last 7 days. Count them.

Output: `[OK] Mailbox accessible — <N> messages in last 7 days` or `[FAIL] could not read mailbox: <reason>`.

**3. Calendar access.** Fetch today's calendar events.

Output: `[OK] Calendar accessible — <N> events today` or `[FAIL] could not read calendar: <reason>`.

**4. SharePoint — Chase Group Construction site.** List the SharePoint sites the user has access to. Confirm the `Chase Group Construction` site is visible (site hostname `chasegroupcc.sharepoint.com`, path `/sites/ChaseGroupConstruction`).

Output: `[OK] Chase Group Construction site visible` or `[FAIL] cannot see the Chase Group Construction SharePoint site — message Chase`.

**5. SharePoint — top-level project folders.** Drill into the `Chase Group Files` document library on the Chase Group Construction site. Confirm these subfolders are visible:
- `1. PRECONSTRUCTION`
- `2. PROJECTS`
- `3. CGC KNOWLEDGE BASE`
- `4. MISCELLANEOUS`

Output: `[OK] All four top-level folders visible` or `[WARN] missing: <list of missing folders>`.

**6. Personal Cowork workspace.** Navigate to `Chase Group Files/4. MISCELLANEOUS/Claude/Cowork-Personal/` and list its subfolders.

Naming convention: each subfolder is the user's first name in lowercase (e.g. `chase`, `alex`, `shawnee`). Look for one that plausibly matches the signed-in user's first name or email local-part.

Output options:
- `[OK] Personal workspace at Cowork-Personal/<name>/`
- `[WARN] No personal workspace yet — message Chase to create Cowork-Personal/<your-first-name>/ with private access for you`

**7. Claude Code platform sanity.** Confirm `~/.claude/CLAUDE.md` exists and contains the company-wide instructions. Confirm at least one subagent is present in `~/.claude/subagents/`.

Output: `[OK] Platform config present — <N> subagents loaded` or `[FAIL] platform config missing — re-run quickstart.ps1`.

---

## Final summary

After all checks, print a clean block like:

```
Chase Cowork - first-run check
==============================
[OK]   Microsoft 365 sign-in
[OK]   Mailbox accessible
[OK]   Calendar accessible
[OK]   SharePoint site visible
[OK]   Top-level folders visible
[OK]   Personal workspace exists
[OK]   Platform config loaded
```

Then end with:
- If everything passed: "You're set up. Try asking me 'What's on my calendar tomorrow?' or 'Find emails from Mitchell about FPK this week.'"
- If any FAIL/WARN: list the specific items and a one-line action ("Message Chase to: create my Cowork-Personal/<name>/ folder", "Sign out and back in with your @chasegroupcc.com account", etc.)

Do not run any other tasks. Do not draft emails. Do not start a project review. Only run these health checks and produce the summary.
