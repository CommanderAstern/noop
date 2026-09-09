# Strength zones and menu review

Reviewed against personal baseline `b09b3a83`. Change-size, testing, breaking-change
and model-context skills were applied independently. No persisted workout schema or
BLE command changes. Model-context requirements do not apply to these UI changes.

1. **P2 — Zone rail can clip offset segments** (`Strand/Screens/StrengthHeartRateView.swift:31`).
   The inner stack must occupy the entire available width before capsule clipping;
   offsets do not increase its layout width. Fixed with an explicit full-width frame.
2. **Boundary follow-up — Closely spaced fractional thresholds can skip integer zones**
   (`Strand/App/StrengthZoneScale.swift:25`). Next-zone text now uses the classifier
   at the next whole-BPM threshold rather than assuming the next numbered zone is reachable.
   Covered by the close-boundaries regression test.
3. **P3 — Persisted toggle makes screenshot content nondeterministic**
   (`Strand/Screens/StrengthSummaryView.swift:16`). The DEBUG demo now sets the zone
   preference explicitly. Focused captures cover both shaded and plain summaries.

Tests cover classification/range agreement, custom boundaries above HR maximum,
clipped scale coordinates, adjacent graph bands, nonoverlapping ticks, snapshot
consistency, and timed versus legacy/unfinished/out-of-window set marks. Apple builds,
app-hosted tests and actual simulator screenshots run in the PR workflow.
