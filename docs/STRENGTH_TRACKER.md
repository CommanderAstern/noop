# Strength workouts in NOOP Lab

Open **Workouts → Open workouts**. The same entry is available inside the
live heart-rate workout screen. Strength sessions are independent of the existing
heart-rate activity log: no strap or heart-rate samples are needed to save a lift.

## Workflow

1. **Train** contains saved training days and editable Upper, Push, Pull and Leg
   starting templates. Set your own weights, or start an empty workout.
2. Add an exercise or gym machine. Search by exercise/equipment, or create a custom
   name and equipment label (for example, "Chest press" / "Gym machine 4").
   The equipment library uses bundled AI-generated illustrations with a consistent
   silver/charcoal/mint style. They work offline and represent equipment categories,
   not a specific manufacturer's machine or exercise-form instruction. Custom entries
   can include your own photo. See STRENGTH_ARTWORK.md for the asset list and prompts.
3. Enter reps and weight for each set. Use kg or lb. Zero means no external load;
   use a consistent convention for pairs of dumbbells (such as combined weight).
4. **Live** shows current BPM and your configured HR zones, with one Start/Complete
   button. Start a warm-up or working set, then complete it to begin rest. There is
   no HR graph during training. **Exercises** contains the full set table and targets.
5. Adjust rest only within an exercise (0–30 minutes, in 15-second increments).
   Changes affect future sets. Start the next set to end rest early or after overtime.
   Zero disables the countdown but still records elapsed rest. Actual rest ends at
   an explicit next-set start, not at countdown zero. A completion without a recorded
   start cannot establish actual rest and is marked unknown.
6. Use **•••** for Undo last set, editing completed sets and notes. Undo cancels
   the affected countdown and marks affected timing as unknown. Reusable templates
   preserve targets, warm-ups and exercise rest settings but clear timing and completion.
7. **Minimize workout** stays at the bottom. The app-wide resume bar preserves the
   session across tabs. Dynamic Island and Lock Screen show the rest clock and next
   exercise, with Open workout; they do not contain rest adjustments or BLE actions.
8. Finish to see the summary, then revisit **History** or compare same-rep working
   loads in **Progress**. Unfinished sets remain explicitly incomplete. Personal
   records compare the same exercise identity against earlier sessions, excluding
   warm-ups, ties and first observations. Distinguish different machines by name.

Numeric edits use an explicit Save action. Invalid or incomplete text cannot be
saved. kg is the canonical unit,
so changing the display unit does not change recorded load.

## Rest alerts

Both alert options default off. Wrist cues also honor the app-wide **Wrist alerts** master in Automations. **WHOOP wrist cue** attempts one acknowledged
`runHapticsPattern` command with one loop, through the existing BLEManager mapping.
WHOOP 5/MG retains its existing 0x13 / MaverickHaptics mapping. This deliberately
does not call `buzzStrapOnce()`, whose existing explicit-user sequence sends both a
three-loop haptic pattern and `runAlarm`. No firmware wake alarm is armed or changed.

The countdown is an absolute deadline owned by AppModel, not a view timer. At the
deadline, consumption is written atomically before issuing a wrist command. Only
a ready bonded connection can attempt the cue, within two seconds of the deadline,
while execution remains fresh. The app timer and workout HR callbacks check the same
durable countdown, including with the screen off using the existing `bluetooth-central`
background mode. A monotonic execution gap longer than two seconds suppresses the cue,
even if a delayed callback arrives within the deadline grace. Late, disconnected and
disabled completions are consumed without retry. Foreground resume and process relaunch
consume expired rests silently. A future rest can continue.
There are no end-of-countdown ticks, repeated alarms, or reconnect catch-up alerts.

One command attempt is not a guarantee of one physical motor response. The user confirmed
the foreground cue on WHOOP Peak 5.0; screen-off delivery still needs hardware testing.
Bluetooth background execution is best effort, not an exact timer guarantee. iOS may
suspend or terminate the app. Do not force-close NOOP Lab during a workout. No audio,
location, or firmware alarm workaround is used to keep the rest timer alive.

Enable **Phone notification** and allow notifications for fallback while the app is
locked, suspended or terminated. iOS delivers the nonrepeating local notification;
it does not grant the app guaranteed execution to send BLE at the deadline. Focus,
notification permissions and phone sound settings can affect presentation. OS-delayed
notification presentation is outside the app's control. Next-set start, undo, replacement, finish
and discard cancel pending requests; foreground stale requests are suppressed.

## Persistence

Active workout, completed history, custom exercises, routines, preferences and the
rest consumption marker share one versioned, atomic JSON file under Application
Support/StrengthWorkouts/v1.json. On iOS, the directory and document explicitly use
protection until first user authentication, matching the background BLE database.
They remain encrypted and become available after the first unlock since boot, including
subsequent screen locks; existing valid documents are migrated on load. Save failures are visible and prevent associated
side effects. Corrupt or newer-version data is not silently overwritten. This is
separate from NOOP's SQLite database and existing `.noopbak` database exports.
App updates retain the data; deleting the app deletes its local strength data.

The document now uses schema v2 at the existing path. Before the first v2 write,
the original v1 bytes are retained once as `before-v2.json` with the same encrypted
protection. Older binaries reject v2 rather than overwriting it; an app downgrade
does not automatically restore the backup. Existing active countdown IDs and
consumption survive upgrade. Legacy sessions retain unknown/partial rest coverage;
NOOP never invents earlier rest or exercise start times. User photos are resized
to a local thumbnail; built-in illustrations are original schematic equipment art.

## Research and boundaries

WHOOP's documented exercise selection, editable reps/loads, rest flow, reusable
workouts and history informed the interaction pattern. This feature is a lifting
log and does **not** reproduce WHOOP's proprietary muscular-load or strain model.

- [WHOOP Strength Trainer workflow](https://www.whoop.com/us/en/thelocker/podcast-219-behind-the-development-of-the-all-new-strength-trainer/)
- [WHOOP Strength Trainer overview](https://www.whoop.com/us/en/thelocker/introducing-strength-trainer-a-new-way-to-quantify-the-impact-of-your-strength-training/)
- [Apple local notification delivery](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/SchedulingandHandlingLocalNotifications.html)
- [Apple Core Bluetooth background limits](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)

## Install and test on iPhone

Update the existing **NOOP Lab** installation through its SideStore source with
Wi-Fi and LocalDevVPN connected, following [personal setup](PERSONAL_DEVELOPMENT.md).
Do not delete the app to update it. Keep the working version available for rollback.

- Add a built-in machine and a custom exercise. Log 2 sets, switch kg/lb and confirm
  conversion; close and reopen the screen, then force-close and restart the app.
  Exercises, weights and completed sets should survive.
- Save a routine, finish, inspect history, then start the routine. Its targets should
  match, with no sets already marked done. Finish/restart must not duplicate history.
- With WHOOP connected, wrist cue enabled, and the Automations Wrist alerts master on, set rest to 15 seconds and complete a
  set. Keep the app active. Verify one wrist cue at zero and none for another minute.
  If the strap ignores it, use phone alerts and report strap model/firmware.
- Start rest, navigate to another tab, and keep the app active. Check one cue at zero.
- Start rest and then start the next set, Undo, complete another set, Finish, or Discard. Check that
  no cancelled countdown cues arrive.
- Repeat with 15-, 90- and 180-second rests: lock the phone immediately after completing
  a set, keep WHOOP nearby, and check for one wrist cue at zero with no repeats. Also
  test while another app is visible. Screen-off delivery is best effort and must be
  checked on the actual strap; a simulator cannot establish physical delivery.
- Disconnect WHOOP before zero, reconnect afterward: no late wrist cue. Lock the phone
  and reopen after zero: no additional catch-up cue, whether the locked cue fired or not.
- Force-close during a rest and reopen after zero: no wrist cue replay. Verify the
  next fresh rest works. Repeat early start, undo, replacement and finish before locking.
- Enable phone notifications. Lock the phone through a countdown and verify one phone
  alert. Repeat after force-closing. Reopen and verify that the rest is complete.
- Deny notifications and verify the settings message explains the missing fallback.

Simulator screenshots use clearly synthetic demo workouts through the existing
DEBUG-only demo-screen harness; they show the actual SwiftUI screens. No demo data
or screenshot route is available in the published Release build.

## Heart rate and workout load

The iPhone **More** tab has a dedicated **Strength Training** entry at the top.
It opens the training hub or resumes the existing session without creating another workout.
Live heart rate uses one panel with named zones, inclusive BPM ranges, a continuous
bar, and the next zone boundary. All boundaries come from the current profile;
fractional thresholds round upward to preserve whole-BPM classification. Closely
spaced custom thresholds can omit bar labels to prevent overlap; the current range remains visible.

Completed graphs have an optional **Zones** overlay with horizontal bands, names and
BPM ranges. Its preference persists. Set intervals appear in a separate strip using
the same chart time scale; completions with unknown starts remain dots. **Time in zones**
shows names, ranges and recorded durations even when chart shading is off. Zone labels
and duration totals refresh together from the same profile snapshot. No live HR graph is added.

Completed summaries and history show completed sets, reps, and external volume load
(completed reps times logged weight), plus an HR graph and average/peak HR. Volume
load is not muscular strain; it excludes unlogged body mass and machine mechanics.
The cardio estimate reuses NOOP's existing independent HR-reserve/TRIMP scorer on
its 0–100 scale, with current profile settings and resting-HR fallback. It is not
WHOOP Strain, and no muscular/cardio percentage split is inferred.

The graph reads the existing local HR database within the workout's saved start/end
times. It breaks lines across gaps longer than one minute; a short or insufficient
recording has no cardio score. Sync can later fill missing HR. Deleting the HR
database removes the graph, while the separately stored lifting log remains.
Completed summaries refresh every 15 seconds while visible to show later sync data.
Select an exercise to highlight its recorded set intervals in the strip, or scrub the graph for
BPM and exercise context. Completions without starts use markers, not invented bands.
Time in zones uses the current profile's custom boundaries when configured.
The durable active session
owns one realtime-HR request, released on finish/discard; iOS suspension still limits
live capture. Metrics never create another HR workout or add a second day-strain entry.

Check graph/average/peak after a recorded session, revisit after restarting, and test
a disconnected interval: the graph must show a gap, not a continuous invented trace.
Change kg/lb and undo a set: volume must convert or decrease to match completed sets.
See [muscular-load research](MUSCULAR_LOAD_RESEARCH.md) for the data needed to develop
and validate an independent muscular-load estimate.
