# Project Matching Notes — fill in per project

The `Email.Projects` array in `NuclearSystemChase\backend\appsettings.json` is the authoritative list of aliases + keywords used to route incoming emails. Chase, fill in the blanks below and I will merge them in so routing catches emails that reference a project by its owner, architect, address, or a key sub instead of the project name itself.

For each project, add anything that — if it appeared in a subject or body — would be an unambiguous tell. The goal is zero misses.

---

## FPK
- **Project number / contract #:** `24-088` (confirmed from handover docs)
- **Owner / client name:**  FPLJ, LLC / Mitchell Rotolo or Mitch Rotolo or Jason Dulin or Adam Johnson
- **Site address:**  6004 Johnston St Lafayette LA 70508
- **Architect firm + lead:** Ritter Maher Architects
- **Key subs (MEP, concrete, steel, etc.):**  Maxtec , Lambright, Broughton's Electric, Wolf Plumbing, Chapman's AC, Pye Barker  
- **Other unambiguous keywords:**  FPK , Fat Pat's Kitchen, Fat Pats, 

## 800 E Farrel
- **Project number:** TODO:
- **Owner / client name:** TODO:
- **Site address:** 800 E. Farrel (confirmed)
- **Architect firm + lead:** TODO:
- **Key subs:** TODO:
- **Other keywords:** TODO:

## Caddy Shack
- **Project number:** TODO:
- **Owner / client name:** TODO:
- **Site address:** TODO:
- **Architect firm + lead:** TODO:
- **Key subs:** TODO:
- **Restaurant brand / franchise (confirm if franchise):** TODO:
- **Other keywords:** TODO:

## Gifted Daycare
- **Project number:** TODO:
- **Owner / client name:** TODO:
- **Site address:** TODO:
- **Architect firm + lead:** TODO:
- **Key subs:** TODO:
- **Exact brand name (Gifted Daycare vs Gifted Academy vs …):** TODO:
- **Other keywords:** TODO:

## Smash
- **Project number:** TODO:
- **Owner / client name:** TODO:
- **Site address:** TODO:
- **Brand / business type (Smashburger franchise? a named restaurant? something else?):** TODO:
- **Architect firm + lead:** TODO:
- **Key subs:** TODO:
- **Other keywords:** TODO:

## Woodhouse
- **Project number:** TODO:
- **Owner / client name:** TODO:
- **Site address:** TODO:
- **Brand (Woodhouse Spa franchise? named residence?):** TODO:
- **Architect firm + lead:** TODO:
- **Key subs:** TODO:
- **Other keywords:** TODO:

## 110 Production
- **Project number:** TODO:
- **Full street address (Production Dr? Production Blvd? which city):** TODO:
- **Owner / client name:** TODO:
- **Architect firm + lead:** TODO:
- **Key subs:** TODO:
- **Other keywords:** TODO:

---

## Cross-project matching hints

Some emails reference people/firms that work across multiple projects. These are NOT project-specific aliases — they should trigger a **disambiguation pass**, not an auto-route. Fill in:

- **Architect firms you use repeatedly:** TODO:
- **MEP engineers you use repeatedly:** TODO:
- **Civil engineers you use repeatedly:** TODO:
- **Repeat-hire GC-side supers:** TODO:
- **Frequent sub firms that span projects:** TODO:

When these appear without an explicit project tell, the Email Agent should ask rather than guess.

---

## Mailboxes in scope

Confirmed with Chase 2026-04-21:

1. `derek@chasegroupcc.com` — Derek Hebert (currently the only one actually wired; staged in `Email.Mailbox`)
2. `chase@chasegroupcc.com` — Chase's corporate (primary)
3. 'alexh@chasegroupcc.com' - Alex Hannie (Project Manager)
4. 'We want to have all emails from sharepoint. They are all connected now through the global login'
5. Chase's personal email — **TODO: which address?** Note: if this is Gmail, ongoing monitoring requires Gmail API, not Microsoft Graph. The historical Gmail Takeout .zip can be imported regardless.
6. Brandon Tony — PST file only (one-time historical import after IT locates it)

## How to fill this out

Either edit this file directly (any format that's readable works) or paste a block at me and I'll merge it into `appsettings.json` for you. Aim for quantity over polish — duplicates are fine, the matcher de-dupes.
