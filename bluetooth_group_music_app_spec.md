# Bluetooth Group Music & Voice-Ducking App --- Product Specification

**Document status:** Draft v1.0\
**Target platform:** Flutter (Android first; iOS subject to platform
validation)\
**Backend:** None\
**Connectivity:** Bluetooth Low Energy (BLE) for discovery, pairing,
synchronization, and group control

## 1. Product overview

Build a mobile app that lets a small group of nearby phones play the
**same music in sync**. One phone creates a listening room and acts as
the host. Other phones join over Bluetooth.

When someone in the group starts speaking, music volume should
automatically decrease (audio ducking) so the conversation can be heard.
When the person stops speaking, music gradually returns to its previous
volume.

The app must work without accounts, cloud services, or a backend.

## 2. Important technical decisions and constraints

### 2.1 Synchronize playback; do not stream music over BLE

BLE is suitable for sending small control messages, but it is not
designed to carry continuous, high-quality music audio. Therefore, the
recommended design is:

-   Every phone plays the same audio track from a local file.
-   The host shares track identity and playback commands with peers over
    BLE.
-   Each peer must already have the same track available locally, or
    obtain it through an explicit local file-transfer/import flow.
-   BLE carries commands and timing information, not music audio.

**MVP assumption:** All participants import the same audio file before
joining. The app compares a file fingerprint (for example, SHA-256) to
verify that the files match.

A future file-sharing feature could transfer audio between nearby
devices, but it should be treated as a separate feature. BLE file
transfer can be slow; investigate platform-supported Bluetooth transfer
or a local Wi-Fi transfer option before committing to it.

### 2.2 Music service restrictions

The MVP should use user-provided local audio files. Do not assume that
the app can capture or redistribute audio from Spotify, YouTube Music,
Apple Music, or other third-party apps. Those services have their own
playback, DRM, and licensing restrictions.

### 2.3 Android and iOS differences

-   Android should be the first implementation target because background
    audio, microphone access, and Bluetooth behavior are more
    configurable.
-   iOS may restrict background Bluetooth, microphone, and simultaneous
    audio behavior. Validate the required behavior on real iPhones
    before promising full parity.
-   Do not claim that every phone can play perfectly synchronized audio
    through its built-in speaker. Bluetooth scheduling, device latency,
    and operating-system audio buffers introduce drift.
-   The app should measure playback position and periodically correct
    drift. Define a practical sync tolerance during device testing.

## 3. Goals

1.  Create a nearby group music session without a server.
2.  Discover and connect nearby participant devices using Bluetooth.
3.  Play the same locally available track on all connected phones.
4.  Keep playback reasonably synchronized.
5.  Detect speech through each participant's microphone.
6.  Lower music volume while speech is detected and restore it smoothly
    afterward.
7.  Allow the host and participants to pause, resume, leave, and manage
    the session.

## 4. Non-goals for the MVP

-   Cloud accounts, user profiles, login, or backend APIs.
-   Internet-based music streaming.
-   Streaming raw microphone audio to other participants.
-   Voice calls, group chat, or speech recording.
-   Guaranteed sample-accurate synchronization across phones.
-   Automatic transfer of tracks from commercial music services.
-   Large groups. Start with a small group and validate BLE reliability.

## 5. User roles

### Host

-   Creates the room.
-   Selects the local audio track.
-   Starts, pauses, resumes, and stops group playback.
-   Can remove a participant and close the room.

### Participant

-   Scans for nearby rooms.
-   Joins the host's room.
-   Confirms that the matching track is available locally.
-   Plays in sync with the host.
-   Can leave the room at any time.

## 6. Main user flows

### 6.1 Create a room

1.  User opens the app and grants the required Bluetooth permission.
2.  User taps **Create Room**.
3.  App asks for a room name and displays a short room code.
4.  Host selects a local audio file.
5.  App scans/advertises using BLE and starts the room.
6.  Waiting screen displays connected participants and track status.

### 6.2 Join a room

1.  Participant opens the app and taps **Join Room**.
2.  App scans for nearby BLE advertisements.
3.  Available rooms appear with room name, host, and signal status.
4.  Participant selects a room and completes the connection handshake.
5.  App checks whether the matching track exists locally.
6.  If the track is missing or has a different fingerprint, show a clear
    error and do not join playback.
7.  Once ready, participant waits for the host to start playback.

### 6.3 Group playback

1.  Host taps **Play**.
2.  Host sends a future playback start timestamp and track position to
    all peers.
3.  Each device schedules local playback for that target time.
4.  Devices periodically report their playback position.
5.  Host sends correction commands when drift exceeds the configured
    threshold.
6.  Host pause/resume/seek actions are propagated to peers.

### 6.4 Voice ducking

1.  Each device locally monitors its microphone while the session is
    active and the user has granted microphone permission.
2.  Voice activity detection (VAD) estimates whether speech is present.
3.  When speech is detected, that device lowers its own music volume.
4.  When speech is no longer detected for a configurable release
    interval, volume returns gradually.
5.  No microphone audio needs to leave the device.

**Default behavior:** Local ducking. If a participant speaks near their
phone, that participant's phone lowers its own music. Other phones
continue at their current volume.

**Optional group ducking:** A device can send a small `VOICE_ACTIVE` /
`VOICE_INACTIVE` event over BLE. The host can relay that event so every
phone lowers its volume when any participant speaks. This should be an
optional setting because it may cause unnecessary ducking from
background conversations.

## 7. Functional requirements

### FR-01 --- Bluetooth discovery

-   Scan for nearby app rooms.
-   Advertise a room while the host is active.
-   Display room name, host identifier, and connection state.
-   Stop scanning when no longer needed.
-   Handle Bluetooth being disabled or permission being denied.

### FR-02 --- Secure room joining

-   Use a room/session identifier and a pairing handshake.
-   Require host approval, or use a room PIN for the MVP.
-   Reject unknown or malformed control messages.
-   Do not expose personal information in BLE advertisements.
-   Disconnect participants when the host closes the room.

### FR-03 --- Track matching

-   Support local audio files in a clearly documented set of formats
    (initially MP3 and M4A/AAC; validate decoder support).
-   Calculate a file fingerprint such as SHA-256.
-   Compare the fingerprint with the host's track fingerprint.
-   Show `Track ready`, `Track missing`, or `Track mismatch` for each
    participant.
-   Do not begin synchronized playback until all required participants
    are ready, unless the host explicitly chooses to start without them.

### FR-04 --- Synchronized playback

-   Support play, pause, resume, seek, and stop.
-   Send commands with a target execution time rather than asking every
    phone to play immediately.
-   Estimate clock offset between host and peers using repeated
    request/response messages.
-   Periodically compare playback positions and correct drift.
-   Use small playback-rate adjustments where supported; otherwise
    perform a controlled seek.
-   Show each device's sync state: `Synced`, `Adjusting`, or
    `Out of sync`.

**Initial engineering targets (to validate, not guaranteed):** - Typical
group size: 2--5 phones. - Target steady-state playback drift: under 150
ms where device/platform behavior permits. - Re-sync check: every 5--10
seconds. - Drift correction threshold: configurable; begin testing
around 100--150 ms.

### FR-05 --- Microphone speech detection

-   Request microphone permission with a clear explanation.
-   Run voice activity detection locally.
-   Do not save or upload microphone audio.
-   Use a short activation threshold to avoid reacting to tiny noises.
-   Use a release delay so music does not jump back up between words.
-   Provide a microphone test and sensitivity setting.
-   Stop microphone monitoring when the user leaves the session or
    disables the feature.

### FR-06 --- Audio ducking

-   Store the user's preferred music volume.
-   On speech start, smoothly reduce volume to a configurable duck level
    (default: 25% of the selected volume).
-   On speech end, restore the selected volume over a configurable ramp
    (default: 700 ms).
-   Avoid abrupt volume changes and repeated volume flicker.
-   Provide a toggle to disable ducking.
-   Make local ducking the default; offer group ducking as an optional
    mode.

### FR-07 --- Session and connection resilience

-   Show connection loss clearly.
-   Attempt reconnection for a configurable period.
-   On reconnection, request current host state and seek to the current
    group position.
-   If the host disconnects permanently, offer participants the choice
    to stop playback or continue independently.
-   Handle host app termination and Bluetooth being switched off.

### FR-08 --- User controls

-   Create/join/leave room.
-   Play/pause/seek/stop (host controls).
-   Music volume slider.
-   Ducking enable/disable.
-   Ducking level and release duration settings.
-   Local vs group ducking mode.
-   Participant list and readiness indicators.
-   Connection and synchronization status.

## 8. Proposed Flutter architecture

Use a modular, platform-aware architecture. Keep Bluetooth, audio
playback, and microphone processing behind interfaces so
platform-specific implementations can be replaced.

``` text
lib/
  main.dart
  app/
    app.dart
    router.dart
  core/
    permissions/
    errors/
    models/
  features/
    room/
      data/
      domain/
      presentation/
    bluetooth/
      data/
      domain/
    playback/
      data/
      domain/
      presentation/
    voice_activity/
      data/
      domain/
    settings/
      data/
      presentation/
  services/
    session_coordinator.dart
```

### Core services

  -----------------------------------------------------------------------
  Service                             Responsibility
  ----------------------------------- -----------------------------------
  `BluetoothService`                  BLE scanning, advertising,
                                      connection lifecycle, GATT
                                      communication

  `RoomService`                       Host/participant roles, room state,
                                      join/leave

  `TrackService`                      Local file selection, metadata,
                                      SHA-256 fingerprint

  `AudioPlaybackService`              Local playback, seek, pause,
                                      volume, playback position

  `SyncService`                       Clock-offset estimation, start
                                      scheduling, drift
                                      detection/correction

  `VoiceActivityService`              Microphone capture and local VAD

  `DuckingService`                    Volume reduction/restoration and
                                      ducking policy

  `SessionCoordinator`                Coordinates room, playback, sync,
                                      voice, and reconnection state
  -----------------------------------------------------------------------

### Suggested Flutter packages to evaluate

Package capabilities and maintenance status must be checked before
implementation.

-   `flutter_blue_plus` --- BLE scanning and GATT communication.
-   `just_audio` --- local audio playback and playback controls.
-   `file_picker` --- selecting local audio files.
-   `permission_handler` --- runtime permissions where applicable.
-   A VAD-capable package or native Android/iOS audio-processing
    implementation --- speech activity detection.
-   `crypto` --- SHA-256 track fingerprinting.
-   `riverpod` or `bloc` --- application state management (choose one).

**Important:** Package support alone does not guarantee background
operation, simultaneous microphone/playback, or low-latency scheduling.
Native Kotlin/Swift code may be required for reliable audio session
behavior.

## 9. Bluetooth communication design

Use BLE GATT for small control messages.

### Suggested GATT layout

-   One custom service UUID for the app.
-   `RoomInfo` characteristic: room metadata and session state.
-   `Control` characteristic: play/pause/seek/stop and configuration
    commands.
-   `Sync` characteristic: clock probes and playback-position reports.
-   `VoiceState` characteristic: optional voice-active state.
-   `ParticipantState` characteristic: readiness and connection status.

The host acts as the BLE peripheral/GATT server where supported;
participants act as central clients. Confirm the intended
central/peripheral roles and simultaneous connection limits on target
devices before finalizing the design. Some platforms and phones impose
restrictions.

### Example control message

``` json
{
  "type": "PLAY_AT",
  "sessionId": "room-session-id",
  "trackHash": "sha256-track-fingerprint",
  "positionMs": 0,
  "hostStartTimeMs": 1730000000000,
  "sequence": 12
}
```

### Example voice event

``` json
{
  "type": "VOICE_ACTIVE",
  "participantId": "participant-02",
  "timestampMs": 1730000001200,
  "sequence": 45
}
```

Messages should include a session identifier and sequence number.
Validate message size and contents. Use authenticated pairing/session
keys rather than trusting any nearby BLE device.

## 10. Voice activity and ducking logic

The microphone should be processed locally. The app needs speech
detection, not speech transcription.

### Initial behavior

-   Frame audio in short windows (for example, 20--30 ms).
-   Compute VAD probability or speech/noise classification.
-   Require speech confidence to remain above a threshold for a short
    activation period.
-   Once speech is active, lower volume quickly but smoothly (for
    example, 150--250 ms).
-   Wait for a silence interval (for example, 800--1200 ms) before
    restoring volume.
-   Restore volume gradually (default 700 ms).

These are starting values for usability testing, not final constants.
Add sensitivity controls because rooms, speakers, and phone microphone
placement vary.

### State machine

``` text
NORMAL
  └─ speech detected consistently → DUCKING

DUCKING
  └─ volume reaches target → DUCKED

DUCKED
  └─ silence detected for release interval → RESTORING

RESTORING
  ├─ speech detected → DUCKING
  └─ original volume restored → NORMAL
```

### Volume calculation

Let `userVolume` be the user's selected volume from 0.0 to 1.0, and
`duckFactor` be the ducking multiplier (default 0.25).

``` text
normalVolume = userVolume
duckedVolume = userVolume * duckFactor
```

Do not overwrite the user's selected volume when ducking. Keep it as a
separate preference so the correct level can be restored.

## 11. UI screens

1.  **Welcome / permissions** --- explain Bluetooth and microphone
    permissions.
2.  **Home** --- Create Room, Join Room, Settings.
3.  **Create Room** --- room name, local track picker, room PIN.
4.  **Discover Rooms** --- nearby room list and connection status.
5.  **Room Lobby** --- participant list, track readiness, host controls.
6.  **Now Playing** --- track title, progress, play/pause, seek, volume,
    ducking state.
7.  **Settings** --- ducking level, release delay, sensitivity,
    local/group mode.
8.  **Permission and connection errors** --- actionable guidance for
    denied permissions, Bluetooth off, or lost connections.

## 12. Permissions and privacy

Request permissions only when the related feature is used.

-   Bluetooth permissions appropriate to the Android OS version.
-   Microphone permission for voice activity detection.
-   Local media/file access as required by the selected file picker and
    OS version.
-   iOS Bluetooth and microphone usage descriptions.

Privacy requirements:

-   Never record or store microphone audio in the MVP.
-   Do not transmit raw microphone audio.
-   Make it clear when microphone-based voice detection is active.
-   Provide an obvious way to disable voice detection.
-   Use minimal participant identifiers.
-   Pair devices securely and avoid putting sensitive data in
    advertisements.

## 13. Error and edge cases

-   Bluetooth disabled or permission denied.
-   Host disappears during discovery or playback.
-   Participant moves out of Bluetooth range.
-   Two participants try to host at once.
-   Track missing or fingerprint mismatch.
-   Participant joins after playback has started.
-   Device receives a phone call or another app takes audio focus.
-   Microphone permission is revoked during a session.
-   Backgrounding, screen lock, battery saver, or OS process
    termination.
-   Host seeks while a participant is reconnecting.
-   Multiple people speak at once.
-   Loud music or environmental noise causes false voice detection.
-   Device does not support the required BLE role or connection count.

## 14. Testing and acceptance criteria

### MVP acceptance checklist

-   [ ] Two supported Android phones can discover and join a room
    without internet.
-   [ ] A participant cannot join playback with a missing or mismatched
    track.
-   [ ] Host play, pause, resume, seek, and stop commands reach
    connected peers.
-   [ ] Playback starts close enough together to meet the measured MVP
    sync target.
-   [ ] Drift is detected and corrected during a 10-minute playback
    test.
-   [ ] Speaking near one phone causes that phone to duck locally.
-   [ ] Music returns smoothly after speech stops.
-   [ ] Ducking does not change the saved user volume.
-   [ ] Optional group ducking propagates voice-state events without
    sending audio.
-   [ ] Leaving a room stops microphone monitoring and releases
    Bluetooth resources.
-   [ ] Reconnection restores the current session state where possible.
-   [ ] Core flows work with no internet connection.

### Device test matrix

Test at minimum: - Two different Android manufacturers and OS
versions. - Two Android phones plus one additional participant. - Screen
on, screen locked, and app backgrounded. - Quiet room, noisy room, music
playing loudly, and multiple speakers. - Bluetooth range changes and
temporary disconnections. - Wired headphones and built-in speakers,
where supported.

Test iOS separately before advertising iOS support.

## 15. Delivery plan

### Phase 1 --- Technical feasibility prototype

-   Validate BLE host/participant communication on target Android
    phones.
-   Validate local audio playback while microphone capture/VAD is
    active.
-   Measure playback start skew and drift.
-   Confirm background and screen-lock behavior.
-   Decide whether iOS can meet the same requirements.

**Exit criteria:** A two-phone prototype can exchange commands, play the
same local track, and duck locally on detected speech.

### Phase 2 --- Android MVP

-   Build room creation and discovery.
-   Add secure joining and track fingerprint validation.
-   Add synchronized playback and drift correction.
-   Add local VAD and smooth ducking.
-   Build lobby, now-playing, and settings screens.

### Phase 3 --- Reliability

-   Reconnection and host-loss handling.
-   Optional group ducking.
-   More participant/device testing.
-   Battery and performance optimization.
-   Accessibility and permission UX improvements.

### Phase 4 --- iOS evaluation and support

-   Implement native iOS Bluetooth/audio-session behavior.
-   Validate background restrictions and microphone/playback
    coexistence.
-   Ship iOS only if the core experience meets agreed acceptance
    criteria.

## 16. Open decisions before implementation

1.  **Platform:** Android-only MVP first, or Android and iOS from day
    one?
2.  **Music source:** Local files only for MVP, or should the app
    include a future device-to-device file-transfer feature?
3.  **Ducking behavior:** Should only the speaker's phone lower its
    music, or should every participant's phone lower music when anyone
    speaks?
4.  **Playback output:** Should each phone play through its own
    speaker/headphones, or is the goal to connect multiple Bluetooth
    speakers to one phone?
5.  **Group size:** Is 2--5 participants a suitable initial limit?

## 17. Recommended MVP scope

Build an **Android-first, 2--5 phone prototype** with local MP3/M4A
files, BLE control messages, synchronized local playback, and local
microphone-based ducking. Add optional group-wide ducking after the
basic experience is stable.

This approach keeps the app backend-free and uses Bluetooth for the part
it handles well: nearby discovery and lightweight coordination. It
avoids relying on BLE to transport continuous music audio, which is the
key technical limitation to design around.
