# Strength flow review — PR #3

The code-review skill ran separate breaking-change, testing, context and change-size
reviews. This list includes every reported issue; overlapping reports are combined.
Line references identify the reviewed revision (`1b5e4b6`, or `a0904c6` for follow-ups).
All correctness findings below have code fixes. Native CI and final PR review remain
the merge gates; simulator results cannot prove physical WHOOP vibration.

1. **P2 — Legacy countdown hidden** (`Strand/Screens/StrengthSessionView.swift:119`).
   Normalize the provable active rest from its saved completion/deadline, retaining
   timer ID and consumed state. Model and controller migration regressions cover it.
2. **P2 — Unknown legacy rest becomes a numeric total**
   (`Packages/StrengthTracking/Sources/StrengthTracking/StrengthWorkout.swift:138`).
   Persist incomplete coverage separately; newly recorded intervals cannot imply
   complete legacy history. A continued legacy-session test keeps its total unknown.
3. **P2 — Restored HR Live Activity survives strength takeover**
   (`StrandiOS/Widgets/LiveActivityController.swift:14`). Enumerate system activities
   even when the process has no cached handle.
4. **P2 — Constant BPM falsely expires** (`Strand/App/AppModel.swift:722`).
   Track valid packet receipt independently of value publication. Repeated identical
   BPM, invalid packets, expiry and disconnect/reconnect are covered by tests.
5. **P2 — Summary does not refresh after backfill**
   (`Strand/Screens/StrengthSummaryView.swift:98`). Restore the cancellation-aware
   15-second refresh while visible, checking cancellation after each database load.
6. **P2 — Background Live Activity request has no foreground retry**
   (`StrandiOS/Widgets/StrengthLiveActivityController.swift:56`). Reconcile persisted
   strength state when the scene becomes active, independently of workout edits.
7. **P2 — Repeated exercise blocks create false PRs**
   (`Packages/StrengthTracking/Sources/StrengthTracking/StrengthFlow.swift:102`).
   Group all current sets by exercise identity before comparing with prior sessions.
   A regression covers a 100 kg block followed by a lighter 65 kg block.
8. **P2 — Photo tasks can overwrite newer selections or race Save**
   (`Strand/Screens/StrengthExerciseLibrary.swift:132`). Use selection-keyed tasks,
   cancellation and identity checks; Save is disabled until that selection resolves.
   Failure clears the obsolete photo and gives a visible retry/save-without-photo choice.
9. **P2 — Backup check decodes all photo history on every save**
   (`Packages/StrengthTracking/Sources/StrengthTracking/StrengthWorkout.swift:247`).
   Cache the successfully read/written disk version. Probe only the version header
   if necessary for migration, and retain original v1 bytes once. Backup tests cover
   byte preservation across later edits.
10. **P2 — Custom HR boundaries ignored** (`Strand/App/AppModel.swift:237` and
    `Strand/App/StrengthWorkoutMetrics.swift:70`). Both live zones and summary splits
    use `profile.hrZoneSet`. The regression verifies custom zones and excludes gaps.
11. **P2 — Live Activity opt-out depends on HR callbacks**
    (`StrandiOS/Widgets/LiveActivityController.swift:38`). Observe the shared preference
    at the app root; a workout without a strap can reconcile immediately.
12. **P2 — Zero-duration rest shows whole-workout time**
    (`StrandiOSWidgets/StrengthLiveActivity.swift:45`). Use the rest's start time for
    elapsed rest when there is no countdown deadline.
13. **P2 — Other supported HR sources lack receipt timestamps**
    (`Strand/BLE/LiveState.swift:66`, follow-up). Standard HR, Oura, Huami and FTMS now
    use the same valid-packet receipt method. Disconnect clears freshness before a
    new source can display an earlier source's reading.
14. **P2 — HR activity re-adoption races asynchronous cleanup**
    (`StrandiOS/Widgets/LiveActivityController.swift:19`, follow-up). Exclude IDs
    awaiting end from adoption, clear only matching cached IDs on completion, and
    never adopt an ended/dismissed activity.
15. **Reviewability — 1,842 changed lines in the initial revision**
    (`Strand/Screens/StrengthWorkoutsView.swift:52`). This exceeds the skill's size
    guidance. Reviewable stages are: model/persistence/tests first (about 310 lines),
    library/template editing, active presentation, history/summary/progress, Live
    Activities, then demos/release text. Splitting requires reorganizing shared view
    helpers and routes, not simply separating new files. The requested feature stays
    in one integration PR, with separate model tests, app tests, build and screenshot
    checks. The skill requires this explanation, not an additional approval gate.

Context-specific model exposure rules were not applicable. Fixtures are synthetic
and DEBUG-only, photos stay local, and no proprietary exercise art is downloaded.
ActivityKit lifecycle and photo-picker behavior additionally require iPhone checks;
the automated model tests do not claim to simulate those system frameworks.

16. **P2 — PR selects the wrong repeated exercise block**
    (`Strand/Screens/StrengthSummaryView.swift:54`, GitHub Codex review of `a0904c6`).
    Achievement selection now resolves the movement containing `record.setID`, so
    the graph highlights the actual winning set's block.

17. **P1 — Preserve repeated HR publications from other sensors**
    (`Strand/BLE/LiveState.swift:64`, GitHub Codex review of `3899c4a`). The receipt
    method now defaults to publishing each valid packet, preserving existing manual
    workout, session-runner and HR activity consumers. WHOOP's existing flood guards
    opt out explicitly. Tests distinguish both publication cadences and invalid HR.
18. **P2 — Opening a starter again overwrites the saved variant**
    (`Strand/Screens/StrengthWorkoutsView.swift:124`, same review). Opening a starter
    constructs a fresh routine and set identities. A regression checks independent
    identities and targets for two variants of the same prototype.
