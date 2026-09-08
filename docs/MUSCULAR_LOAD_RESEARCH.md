# Developing a NOOP muscular-load estimate

No validated muscular-load score is shipped. NOOP currently reports completed
lifting volume and its independent HR-based cardio estimate separately.

## What can be obtained from WHOOP

WHOOP's documented workout API supplies overall activity strain, average/maximum
heart rate and zone durations. Its published schema does not currently include a
muscular/cardio breakdown, exercise-level sets or raw motion. The standard CSV
export has summary data, not the signals needed to infer muscular load uniquely.
Do not subtract NOOP cardio effort from WHOOP overall strain: the scales and
algorithms differ and WHOOP's combination is nonlinear.

Official score display would require a supported data source containing that
field, or an explicitly entered observation labelled as imported from WHOOP.
It does not become a NOOP measurement merely by being displayed here.

## First capture on WHOOP 5.0 / MG

Use NOOP's existing **Test Centre → 5/MG Raw Data Collector**. This already supports
bounded motion sessions, timestamped markers and export. No new raw BLE commands
or automatic continuous research recording are needed for this investigation.

1. Record strap model, firmware, wrist/placement, units and local timezone. Keep
   placement consistent. Confirm pairing and a working HR feed.
2. Start a short raw-data session. Record a stationary interval followed by one
   familiar exercise set. Mark set start/end and annotate exercise, equipment,
   reps, external weight, and whether dumbbell weight is combined or per hand.
3. Stop explicitly. Check that the collector reports complete IMU seconds and
   export the session locally. Verify timestamps, approximate 100 Hz sample
   cadence, acceleration units, gyro units and missing data before extending capture.
4. Pair recordings with the lifting log and, when available, the official WHOOP
   workout summary and muscular/cardio breakdown for the same time window.
   Do not assume the official app and NOOP can concurrently capture from every
   firmware; establish this with a short connectivity test first.

## Useful labels and progression

For each set collect exercise and machine identity, start/end timestamps, reps,
external weight and units, perceived effort or reps in reserve, and placement.
Body weight helps interpret bodyweight movements. A known comfortable baseline
or estimated 1RM can describe relative load; maximal testing is not required.
An optional reference video or rep-speed measurement can validate segmentation,
but it should only be collected deliberately and stored locally.

Begin with a small set of familiar movements at usual loads. Repeat some sessions
under similar conditions and include normal variations in reps, tempo and rest.
One wrist does not directly measure all body segments, muscle recruitment, machine
lever ratios, or tissue stress; these are modelling limitations, not missing UI fields.

First analyse signal quality and set/rep segmentation. Then evaluate interpretable
features such as external volume, relative load, set duration and motion patterns.
Define an independent metric and its units before fitting anything. If comparison
with WHOOP is a goal, reserve entire workouts for evaluation; never train and test
on different reps from the same session and claim generalisation. Compare against
simple volume-only baselines, report errors and repeatability by exercise, and
withhold scores where input coverage or validation is inadequate.

A personal pilot can establish feasibility. It cannot validate a universal
physiological score. More data may improve agreement with WHOOP outputs but does
not recover WHOOP's proprietary formula or establish biological accuracy.

## Data handling

Keep exports and health observations outside the public repository. CI tests use
synthetic data only. Share only deliberately selected files; credentials are not
needed for local analysis. This document does not enable uploading or collection.

## Sources

- [WHOOP muscular-load methodology and validation](https://www.whoop.com/us/en/thelocker/the-research-and-development-behind-strength-trainer/)
- [WHOOP strain inputs and unpublished formula](https://www.whoop.com/us/en/thelocker/how-does-whoop-strain-work-101/)
- [WHOOP public API schema](https://developer.whoop.com/api/)

Documentation checked September 8, 2026. Capture support is based on the existing
NOOP decoder and collector; it still needs verification on the user's strap.
