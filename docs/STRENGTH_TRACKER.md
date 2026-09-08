# Strength workouts in NOOP Lab

Open **Workouts → Open strength tracker**. The same entry is available inside the
live heart-rate workout screen. Strength sessions are independent of the existing
heart-rate activity log: no strap or heart-rate samples are needed to save a lift.

## Workflow

1. Start a strength workout, or start from a saved routine.
2. Add an exercise or gym machine. Search by exercise/equipment, or create a custom
   name and equipment label (for example, "Chest press" / "Gym machine 4").
3. Enter reps and weight for each set. Use kg or lb. Zero means no external load;
   use a consistent convention for pairs of dumbbells (such as combined weight).
4. Tap **Complete set** once. This saves completion and starts the configured rest
   countdown. Add more sets as needed. Undo cancels that set's current rest.
5. Rest defaults to 90 seconds, adjustable in 15-second increments up to 30 minutes.
   Zero disables auto-rest. Duration changes apply to the next completed set.
   Skip cancels the current rest. Completing another set replaces it.
6. Save the current exercise order and set targets as a reusable routine. Routine
   reuse makes new session/set IDs and clears all completion marks.
7. Finish and save to **Strength history**. Unfinished sets stay explicitly marked
   as not completed. Closing the screen keeps the workout running and saved.

Valid numeric edits save as they are typed. Invalid or incomplete text is marked
and cannot complete a set; invalid text is not persisted. kg is the canonical unit,
so changing the display unit does not change recorded load.

## Rest alerts

Both alert options default off. **WHOOP wrist cue** attempts one acknowledged
`runHapticsPattern` command with one loop, through the existing BLEManager mapping.
WHOOP 5/MG retains its existing 0x13 / MaverickHaptics mapping. This deliberately
does not call `buzzStrapOnce()`, whose existing explicit-user sequence sends both a
three-loop haptic pattern and `runAlarm`. No firmware wake alarm is armed or changed.

The countdown is an absolute deadline owned by AppModel, not a view timer. At the
deadline, consumption is written atomically before issuing a wrist command. Only
an active app with a ready bonded connection can attempt the cue, within two seconds
of the deadline. Late, inactive, disconnected and disabled completions are consumed
without retry. Relaunch consumes expired rests silently. A future rest can continue.
There are no end-of-countdown ticks, repeated alarms, or reconnect catch-up alerts.

One command attempt is not a guarantee of one physical motor response. Actual wrist
vibration needs testing on your strap; a command acknowledgement cannot confirm it.
The intentionally shorter single-command cue may be ignored by some firmware.

Enable **Phone notification** and allow notifications for fallback while the app is
locked, suspended or terminated. iOS delivers the nonrepeating local notification;
it does not grant the app guaranteed execution to send BLE at the deadline. Focus,
notification permissions and phone sound settings can affect presentation. OS-delayed
notification presentation is outside the app's control. Skip, replacement, finish
and discard cancel pending requests; foreground stale requests are suppressed.

## Persistence

Active workout, completed history, custom exercises, routines, preferences and the
rest consumption marker share one versioned, atomic JSON file under Application
Support/StrengthWorkouts/v1.json. Save failures are visible and prevent associated
side effects. Corrupt or newer-version data is not silently overwritten. This is
separate from NOOP's SQLite database and existing `.noopbak` database exports.
App updates retain the data; deleting the app deletes its local strength data.

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
- With WHOOP connected and wrist cue enabled, set rest to 15 seconds and complete a
  set. Keep the app active. Verify one wrist cue at zero and none for another minute.
  If the strap ignores it, use phone alerts and report strap model/firmware.
- Start rest, navigate to another tab, and keep the app active. Check one cue at zero.
- Start rest and then Skip, Undo, complete another set, Finish, or Discard. Check that
  no cancelled countdown cues arrive.
- Disconnect WHOOP before zero, reconnect afterward: no late wrist cue. Repeat by
  locking the phone and reopening after zero: no catch-up wrist cue.
- Enable phone notifications. Lock the phone through a countdown and verify one phone
  alert. Repeat after force-closing. Reopen and verify that the rest is complete.
- Deny notifications and verify the settings message explains the missing fallback.

Simulator screenshots use clearly synthetic demo workouts through the existing
DEBUG-only demo-screen harness; they show the actual SwiftUI screens. No demo data
or screenshot route is available in the published Release build.
