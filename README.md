# Pomodoro Todo — KDE Plasma Widget + Mobile App

![Screenshot](screenshot.png)

A KDE Plasma 6 panel widget that combines a **Pomodoro timer** with a **todo list** — everything you need to stay focused, right in your taskbar. Pairs with a **Flutter mobile companion app** (Android, iOS, Linux, macOS) that stays in sync via WebDAV.

---

## Features

**Pomodoro Timer**

- Focus sessions (default 25 min) → Short breaks (5 min) → Long break after every 4 sessions (15 min)
- Session dots showing progress through a Pomodoro cycle
- Start / Pause / Reset Current / Reset All / Skip controls
- Timer countdown shown directly in the panel bar while running
- Desktop notifications when each session ends (toggleable)

**Todo List**

- Add and remove tasks
- Check off completed tasks (shown as strikethrough)
- Expand any task to add a description with full **Markdown support** (bold, lists, links, inline images)
- Edit task titles inline with a pencil button
- Clear completed tasks with one click (confirmation required)
- Tasks persist across sessions (saved in widget config)
- Set per-task **reminders** that fire a desktop notification at the chosen time

**Eisenhower Matrix**

- Toggle between flat list view and a **2×2 priority matrix** (list/grid icon in the tasks header)
- Each task carries **Urgent** and **Important** flags, shown as a colour dot on the task row
- Q1 — Do First (red): urgent + important
- Q2 — Schedule (blue): important, not urgent
- Q3 — Delegate (orange): urgent, not important
- Q4 — Eliminate (grey): neither
- Priority flags are preserved on every sync round-trip (WebDAV, Google Tasks)

**Workspaces**

- Organize tasks into multiple independent lists — e.g. *Work*, *Personal*, *Games*
- Switch between workspaces with a tab bar inside the popup
- Add new workspaces with the **+** button; rename with the pencil icon; delete with the trash icon (confirmation required, only shown when more than one workspace exists)
- A *Default* workspace is created automatically on first launch
- Existing tasks are migrated automatically when upgrading from an older version

**WebDAV Sync** *(optional)*

- Bidirectional task sync to any WebDAV server (Nextcloud, ownCloud, a plain nginx share, etc.)
- **Live timer sync** — when the timer starts/pauses on one device, all synced devices update within ~10 seconds
  - Uses an absolute UTC `endTime` timestamp so every device counts down independently without extra network traffic
  - Last-write-wins with ISO-8601 `lastModified` timestamps for conflict resolution
- ETag-based optimistic locking prevents data loss on concurrent writes

**Google Tasks Sync** *(optional)*

- Bidirectional sync with Google Tasks
- Assign each workspace to a Google Task list
- Auto-sync on save and/or on a timer
- Last-write-wins conflict resolution
- Credentials stored securely in KWallet

**Fully Configurable**

- Focus and break durations
- Auto-start next session when a timer ends
- Active color (focus) and break color
- 4 separate tray icons: Focus / Paused+Idle / Short Break / Long Break
- Panel display mode: icon + timer, icon only, or timer only
- Notifications on/off
- Auto-expand new tasks and jump straight to the description field

**Localization**

- English (default)
- Portuguese — Brazil (pt_BR)
- Simplified Chinese (zh_CN)
- Falls back to English automatically

---

## Mobile Companion App

A Flutter app for **Android, iOS, Linux, and macOS** that mirrors the plasmoid's full feature set.

**Timer**

- Same Pomodoro cycle logic as the desktop widget
- Persistent foreground notification on Android showing time remaining ("Focus ends at 14:35")
- OS-level exact alarm fires even when the app is killed — you never miss a session end
- Vibration + sound on session complete
- Live sync with the KDE plasmoid via WebDAV — start a session on your phone, watch the desktop count down (and vice versa)

**Tasks**

- Full workspace management, task CRUD, Markdown descriptions, reminders
- **Eisenhower Matrix view** — same 2×2 grid with colour-coded quadrants
- Priority dots on every task tile
- Google Tasks sync with the same bidirectional algorithm as the desktop

**Settings**

- WebDAV server URL, username, password (stored in the secure keystore)
- Google Tasks OAuth2 (Client ID, sign in/out, per-workspace list assignment, auto-sync toggle)
- Timer durations, auto-start, notification preferences

### Building the mobile app

```bash
cd mobile
flutter pub get
flutter run                        # debug on connected device/emulator
flutter build apk --release        # Android APK
flutter build linux --release      # Linux desktop
flutter build macos --release      # macOS (requires macOS host)
flutter build ios --release --no-codesign   # iOS unsigned
```

---

## Requirements

**Plasmoid (desktop)**

- KDE Plasma 6
- `gettext` (for compiling translations): `sudo pacman -S gettext`
- `python3` (for Google Tasks OAuth): pre-installed on most distros
- KWallet (for secure credential storage): included in KDE Plasma

**Mobile app**

- Flutter 3.x
- Android SDK / Xcode as appropriate for your target platform
- `libsecret` + a running keyring daemon (GNOME Keyring or KWallet) for the Linux build

---

## Installation

### Plasmoid

```bash
git clone https://github.com/otavioschwanck/pomodoro-todo-plasma
cd pomodoro-todo-plasma
make install        # or: ./install.sh
```

Then restart Plasma:

```bash
make reload
# or manually:
kquitapp6 plasmashell && kstart plasmashell
```

Finally, right-click the panel → **Add Widgets** → search for **Pomodoro Todo**.

### Makefile targets

| Target                      | Action                                   |
| --------------------------- | ---------------------------------------- |
| `make` / `make install` | Compile translations + install plasmoid  |
| `make reload`             | Install then restart plasmashell         |
| `make clean`              | Remove installed plasmoid +`.mo` files |
| `make clean-all`          | Above +`flutter clean`                 |
| `make mobile-run`         | `flutter run` on connected device      |
| `make mobile-build-apk`   | Release APK (split by ABI)               |
| `make mobile-build-linux` | Release Linux binary                     |
| `make mobile-analyze`     | `flutter analyze`                      |

---

## Google Tasks Setup

1. Go to [Google Cloud Console](https://console.cloud.google.com/apis/credentials) and create or select a project
2. Navigate to **APIs & Services → Library**, search for **Tasks API**, and click **Enable**
3. Go to **APIs & Services → Credentials → Create Credentials → OAuth Client ID**
4. Choose **Desktop app** as the application type
5. Copy the **Client ID** and **Client Secret**

**On the plasmoid:** Right-click → **Configure… → Google Tasks**, paste the credentials, click **Connect Google Account**, then assign each workspace to a Google Task list.

**On mobile:** Settings → **Google Tasks**, enter the Client ID, tap **Sign in with Google**, then assign each workspace to a list.

---

## WebDAV / Live Sync Setup

1. Point both the plasmoid (**Configure… → WebDAV**) and the mobile app (**Settings → WebDAV**) at the same server URL, username, and password
2. Enable **Auto-sync** on both sides
3. The timer state file (`timer-state.json`) is written on every start/pause/skip/complete — synced devices update within ~10 seconds while the timer is running, ~60 seconds when idle

---

## Usage

- **Left-click** the tray icon to open/close the popup
- **Middle-click** the tray icon to toggle Start/Pause without opening the popup
- **Right-click** the tray icon for quick actions (Start, Pause, Reset, Skip, Clear Completed Tasks)
- Click the **pin** button (top-right of the popup) to keep the popup open above other windows
- In the popup, press **Enter** or click **Add** to create a task
- Click a task title to expand/collapse its description
- Click the **pencil** icon to edit a task's title; click it again (or press Enter) to save
- In the description area, click the **pencil** icon to switch to edit mode — Markdown is rendered in read mode
- Use the **workspace tabs** to switch lists; click **+** to add a new workspace
- Click the **grid icon** in the tasks header to toggle between list view and Eisenhower Matrix
- Go to **Right-click → Configure…** to adjust durations, colors, icons, and behavior

---

## Releases

Binaries are built automatically by GitHub Actions on every version tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The release includes: Android APK (split by ABI), Linux AppImage, macOS DMG, and an unsigned iOS IPA.

---

## File Structure

```
pomodoro-todo/
├── metadata.json               # Widget metadata (id, author, license)
├── screenshot.png              # Cover image
├── install.sh                  # Build + install script
├── Makefile                    # Common dev tasks
├── .github/workflows/
│   └── release.yml             # CI: builds all platforms + creates GitHub Release
├── contents/
│   ├── bin/
│   │   ├── wallet-helper.sh    # KWallet D-Bus bridge (read/write/clear secrets)
│   │   └── google-auth.py      # OAuth2 PKCE browser flow for Google Tasks
│   ├── config/
│   │   ├── main.xml            # KConfigXT schema (all settings)
│   │   └── config.qml          # Config dialog page list
│   ├── locale/
│   │   ├── pt_BR/LC_MESSAGES/  # Brazilian Portuguese .po/.mo
│   │   └── zh_CN/LC_MESSAGES/  # Simplified Chinese .po/.mo
│   └── ui/
│       ├── main.qml            # Root PlasmoidItem — all state + layout
│       ├── TodoItem.qml        # Single task row delegate (Markdown descriptions, priority flags)
│       ├── WalletHelper.qml    # QML wrapper around wallet-helper.sh
│       ├── WebDavSync.qml      # WebDAV bidirectional sync + live timer sync
│       ├── GoogleTasksSync.qml # Google Tasks bidirectional sync engine
│       ├── ConfigTimer.qml     # Timer settings page
│       └── ConfigGoogle.qml    # Google Tasks settings page
└── mobile/                     # Flutter companion app
    ├── lib/
    │   ├── main.dart
    │   ├── models/workspace.dart           # Task + Workspace data models
    │   ├── state/app_state.dart            # ChangeNotifier — all app state
    │   ├── services/
    │   │   ├── settings_service.dart       # SharedPreferences + secure storage
    │   │   ├── webdav_service.dart         # WebDAV CRUD + ETag locking
    │   │   ├── google_auth_service.dart    # PKCE OAuth2 loopback flow
    │   │   ├── google_tasks_service.dart   # Tasks API v1 wrapper + sync
    │   │   └── notification_service.dart   # Local notifications + exact alarms
    │   └── screens/
    │       ├── home_screen.dart            # Timer + task list/matrix view
    │       ├── settings_screen.dart        # WebDAV + general settings
    │       └── google_settings_screen.dart # Google Tasks OAuth + list assignment
    └── pubspec.yaml
```

---

## License

GPL-2.0-or-later. Free to use, fork and modify.

---

## Authors

**Otávio Schwanck dos Santos** — [otavioschwanck@gmail.com](mailto:otavioschwanck@gmail.com)

**Sparsa Roychowdhury** — [sparsa.roychowdhury@gmail.com](mailto:sparsa.roychowdhury@gmail.com)
