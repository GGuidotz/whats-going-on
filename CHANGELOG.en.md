# What's New

English notes, same format as CHANGELOG.md (the Italian one is the reference). The app uses these when its language
is English; versions missing here fall back to the Italian notes.

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
