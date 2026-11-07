# What's New

English notes, same format as CHANGELOG.md (the Italian one is the reference). The app uses these when its language
is English; versions missing here fall back to the Italian notes.

## 0.7.0 · 2026-11-07

Why is it slow: today's causes in one answer, a week of history, what starts by itself and who intercepts the keyboard.

### New features
- **Why Is It Slow?** A button under the sentence looks for the causes right now with fixed rules and ranks them, most serious first, each with its numbers and what to do: not enough memory, processes busy for a long time, Spotlight, disk, heat, keyboard, orphaned startup items, days since the last restart. With Apple Intelligence on, one click rewrites it in plain words, on your Mac.
- **System processes.** macOS and root processes too (invisible before): one at 95% for 40 minutes shows up in the sentence, in the CPU details and in the answer, with what it does and whether to worry.
- **7-day history.** CPU, memory, swap and free space, one point per minute, in 24-hour and 7-day charts. Numbers only, saved on the Mac; turn it off or delete it in Settings › General.
- **Tools › Startup.** What starts by itself (LaunchAgents and LaunchDaemons) and what's left of apps that are gone. Your user's orphans can be disabled or moved to the Trash, after a confirmation.
- **Tools › Keyboard.** The apps intercepting keys right now, actively or only listening, with the delay measured by macOS. No permissions needed.
- **Two new alerts.** Growing swap (more than 500 MB in 30 minutes) and runaway process (system ones included, for over 10 minutes). If you update, they start off in Settings › Alerts.

### Improvements
- **Disk: alert under 15%.** It used to fire under 10%, when the Mac was already slow; if you had the old default you move to the new one. The sentence and the alert also say in how many days it will be full.
- **Memory explained.** How much data sits in compressed memory, how swap changed in the last 30 minutes and how fast it's writing now; the heaviest apps include their compressed part.
- **Thermal state and Spotlight.** macOS's thermal state and Spotlight indexing in the CPU details; heat that reduces performance enters the sentence.
- **Uptime, always.** No longer only with the panel open; after two weeks the sentence suggests a restart, without alerts.
- **Alerts stay for serious things.** Orphaned startup items, days of uptime and mild heat show in the panel and the sentence, never as notifications.

## 0.6.0 · 2026-10-16

Really uninstall apps, see who uses energy, disk and network, and free up space faster.

### New features
- **Uninstall apps.** The app and everything it leaves in the Library, including the vendor's folder (Google/Chrome), with size and last use. Everything goes to the Trash, after a confirmation.
- **Energy, disk and network per app.** In Tools › Apps: the watts of each app, disk reads and writes, data received and sent.
- **List view with multiple selection.** Next to the map, a table you sort by column: check several items, even from different folders, and move them to the Trash together.
- **Analyze a folder.** Home, Downloads, Documents or any folder, without reading the whole disk.
- **Filter by kind.** Click a kind in the legend and the map shows only that.
- **Search the whole Mac.** Files by name with Spotlight, largest first, even without reading the disk.
- **Recovered so far.** How much you've moved to the Trash since you opened Tools.
- **Power and processor in the panel.** The power adapter and its watts, energy into or out of the battery, capacity in mAh; processor name, load average, uptime.
- **What's New screen.** This page after every update, then in Settings › Updates.

### Improvements
- **Disk reading on every core.** Folders are read in parallel and at high priority: much faster, especially on Apple silicon.
- **Project folders.** Recognized by their project file and grouped by tool (Node.js, Rust, Swift, Python, Gradle…), each with the command that rebuilds it and whether it's rebuilt or downloaded again. The big button only moves those idle for a month.
- **Developer tool caches.** npm, pip, Cargo, Gradle, Homebrew, CocoaPods, Playwright and more in a single tip: they download again on their own.
- **Xcode archives.** A tip of their own: they can't be recreated, so they open in the Finder instead of going to the Trash.

### Bug fixes
- **No more fake projects.** Folders merely named like tool folders (Pods, venv, the global ~/.gradle cache) are no longer offered as rebuildable without their project file.
