# claude-cowork — public bootstrap mirror

This repo is the public face of Chase Group Construction's internal Claude Cowork platform. It contains the bootstrap installer and the company configuration that gets mirrored to each employee's `~/.claude/` directory.

**Source of truth:** the private repo `grantdozier/DTG_Operational_Intelligence_Layer`. Content here is auto-mirrored on every push to `main`.

**Nothing sensitive lives here.** No secrets, no credentials, no PII. Just install scripts and prompt configuration. Secrets live in Azure Key Vault. Per-user M365 access is delegated through Entra App #1 at sign-in time.

## For employees

Install the platform with:

```powershell
iex "& { $(irm https://gist.githubusercontent.com/grantdozier/d940862d23d72cb71cecc3d2d35a36bc/raw/quickstart.ps1) }"
```

That downloads the latest version of this repo, extracts it locally, and runs `bootstrap/setup.ps1`. ~5 minutes. Full docs in `docs/USER_GUIDE.md` of the parent project.

## For maintainers

To push an update:
1. Edit files in the private `claude-cowork/` folder of `grantdozier/DTG_Operational_Intelligence_Layer`.
2. The GitHub Action (TBD — currently manual `git push` here) mirrors changes to this repo on push to main.
3. Employees re-run the same iex one-liner to pick up the update.

Issues / PRs welcome at the parent project.
