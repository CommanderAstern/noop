# NOOP Lab on Windows and iPhone

This fork's `personal` branch is your customization branch. `origin` is
`https://github.com/CommanderAstern/noop.git`; `upstream` is
`https://github.com/ryanbr/noop.git`. `main` is the upstream baseline.
The initial baseline was updated on 2026-09-08; the previous state is saved
locally as `backup/before-personal-setup-20260908`.

## Install and update

Add this URL in SideStore's Sources screen:

https://github.com/CommanderAstern/noop/releases/latest/download/altstore-source.json

Install **NOOP Lab**. It has its own bundle ID (`com.commanderastern.noop`)
and App Group, so it installs beside NOOP with separate data. Keep the working
NOOP app. Export a backup inside NOOP before testing; import a copy into Lab
if you want your existing history. Avoid running both apps against the strap
at the same time. SideStore plus NOOP plus Lab uses the three free app slots.

Keep SideStore and Lab refreshed before their seven-day signing periods expire.
Connect LocalDevVPN and Wi-Fi when installing or refreshing. A new version
is an app update; it does not extend the signing lifetime indefinitely.

## Make a change

Open this repository folder in your editor. Start from `personal`, then make a feature branch:

```powershell
git switch personal
git pull --ff-only origin personal
git switch -c codex/my-change
git status
# Edit and review your changes.
python -m unittest discover -s Tools/personal -p 'test_*.py' -v
git diff --check
git add <the-files-you-changed>
git commit -m "Describe your change"
git push -u origin HEAD
gh pr create --base personal
```

The **NOOP Lab iPhone release** workflow tests the protocol and analytics,
builds the app on GitHub's macOS runner, checks the app/widget identities,
and publishes an IPA, checksum, and SideStore source only after success.
PRs targeting `personal` run the build without publishing. A merge into `personal` starts the release build. You can also use GitHub Actions'
Run workflow button on `personal`. Windows edits the Swift files; the Mac
runner compiles them. iPhone hardware testing still happens on your phone.

Lab versions are `1.<workflow run number>.<attempt>`, independent of upstream's
version numbers. Release tags point to the exact built commit. No Apple ID,
pairing file, signing certificate, or personal health data is sent to GitHub.
SideStore performs Apple signing on your iPhone.

Upstream screens are mainly in `StrandiOS/` and shared `Strand/Screens/`;
shared UI components are in `Packages/StrandDesign/`. Preserve the project
credits and follow `docs/CONTRIBUTING.md` for Bluetooth and database changes.

## Upstream check every three days

The Codex scheduled check uses this local repository and `personal` branch.
Keep the PC on and the desktop app running for local scheduled work.

On each check, fetch origin and upstream. If `personal` is clean, bring in
any fast-forward updates from `origin/personal`, save a backup branch, and
merge `upstream/main`. Review the diff and run relevant available checks.
Preserve personal code, release tooling, app identity and update URLs. Never
reset, force-push, discard unfinished edits, or accept one side of a conflict
blindly. If another task is editing this branch, defer the merge. If conflicts
need a design decision, leave a separate integration branch and report them.

The scheduled check commits successful integrations locally and reports the
changes. It does not push or publish a new phone version automatically. Review
the integration on a feature branch and open a PR into `personal` when you want a new Lab release. If Windows cannot run a
relevant Swift check, the report must say so; the GitHub build gates publication.

## Backups and rollback

Use NOOP's in-app export before experiments that change stored data. Keep
exports outside this public source repository. Git backs up code, not your
phone's health database. Old GitHub releases retain their IPA files for manual
SideStore import; a code rollback does not automatically undo a database change.

To undo a code change, prefer `git revert <commit>` and publish another build.
This preserves history and produces a newer version SideStore can offer.

The app remains native and stores strap data locally. This setup distributes
builds over the internet; it does not add cloud health-data sync or remotely
executed screens.

## Required AI review before merging

The personal branch uses a GitHub ruleset requiring pull requests, passing `iphone`
CI and the `codex-review` status, with no bypass actors. Codex reviews every PR and
new push. As in Inkbook, the gate verifies the authenticated Codex App summary refers
to the current commit, and all review threads must be resolved. A previous commit's
review, a human-authored summary, a label or a failed/in-progress review cannot pass.

The gate runs trusted code from `personal`, never PR scripts with a write token.
After resolving a finding, re-run **Codex review gate** with the PR number if GitHub
has not emitted a comment/review event. New code needs a new connected AI review.
The initial installation can run `python Tools/personal/review_gate.py --pr N --publish`
locally after the connected review, because the workflow does not exist on the base
until that first reviewed PR merges. This still validates real GitHub review metadata;
do not manually mark a missing review successful.

The existing local upstream check remains local-only and is not duplicated. Any
upstream merge to publish must also go through a PR into `personal` and the same gates.
See [the strength tracker guide](STRENGTH_TRACKER.md) for workflow and iPhone tests.
