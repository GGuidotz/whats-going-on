# What's Going On

What's happening on your Mac, in one sentence. [Italiano](README.md)

What's Going On lives in the macOS menu bar and shows CPU, memory and network in very little space: for each reading a
small label stacked one letter under the other, and the value next to it, colored from green to red as the load rises. Network has two lines,
upload and download, each in its own color. Open the panel and the top line tells you the one thing that matters right
now: "All quiet", or "Google Chrome is using 180% CPU for 4 min". Below it, a card per reading with a live graph; click
one for details.

It's a companion to [Cocaine](https://github.com/Mattiakart/cocaine): alerts can show up in its island. Independent
project, not affiliated with Cocaine. Inspired by [Stats](https://mac-stats.com).

## Why is it slow?

The **Why Is It Slow?** button under the sentence looks for the causes right now with fixed rules and ranks them, each
with its numbers and what to do: not enough memory (growing swap, compressed memory), a process busy for a long time
(macOS and root ones included), Spotlight indexing, disk under 15% with an estimate of when it will be full, heat as
macOS reports it, apps intercepting the keyboard, orphaned startup items, days since the last restart. The same
situation always gives the same answer. With Apple Intelligence on (macOS 26), one click rewrites it in plain words, on
your Mac.

## What it shows

| Reading | Details |
|---|---|
| CPU | user and system, processor, load average, uptime, macOS thermal state, Spotlight indexing, processes busy for a long time (system ones included), per-core load (advanced mode), busiest apps |
| Memory | pressure, app, wired, compressed and the data it holds, swap with its change over the last 30 minutes and write speed, apps using the most memory (compressed included) |
| Network | download and upload speed, traffic since launch, local address |
| Temperature | chip and GPU; every sensor in advanced mode |
| GPU | usage and memory (advanced mode) |
| Disk | free and used space, when it will be full at the pace of the last few days |
| Battery and power | level, time left, health, capacity, cycles; power adapter and power flow (what comes in, what goes to the battery); whole-Mac power where macOS exposes it |
| History | 24 hours and 7 days of CPU, memory, swap and free space: one point per minute, numbers only, saved on the Mac and deletable in Settings › General |

By default the menu bar shows CPU, RAM and NET. In Settings › Menu Bar you pick readings, order and style (numbers, or
numbers with a tiny bar graph), spacing and colors (a red-to-green scale, or three colors of your choice), with a preview
on light and dark menu bars. Right-click the item for settings, what's
new, feedback and quit.

On macOS 26 and later the panel, tabs and buttons use Liquid Glass, and the app icon is a layered Liquid Glass icon
(Icon Composer). On macOS 14 and 15 the same elements use the system materials.

## Light

The goal is to stay under 1% CPU. With the panel closed the app only reads what you show in the menu bar and what the
alerts you turned on need: temperatures, the heaviest reading, only from the chip sensors and every 30 seconds by
default; the app list every 10; every process, system ones included, with `ps` once a minute (about 35 ms each
time). The long history takes one point per minute from the same readings. With the menu bar hidden it draws nothing, and with the displays off it slows down. You
can see how much it really weighs in Settings › General. On first launch a short guide helps you pick what to show and
where alerts go.

## Tools

On demand, in their own window (⌘T from the panel, the buttons in the Disk, Memory and CPU rows, or a click on an
alert):

- **Space**: a map of your disk like [GrandPerspective](https://grandperspective.sourceforge.net), each rectangle as big
  as the space it takes, colored by kind (click a kind in the legend to see only that), or a sortable list with
  checkboxes for the Trash. It reads the whole disk on every core, or just one folder. On the right, tips: app caches,
  project folders recognized by their project file (node_modules, target, .venv, DerivedData…) with the tool and command
  that rebuilds them, developer tool caches (npm, pip, Cargo, Gradle, Homebrew…), installers already used, iPhone
  backups, large files not opened in 6 months. What you remove goes to the Trash, always after a confirmation. With
  Full Disk Access the map also sees Mail, Messages, Safari and backups. Plus Search the whole Mac: files by name with
  Spotlight, even without reading the disk.
- **Apps**: what's heavy on memory, keeps the CPU busy, uses energy, works the disk or uses the network, with Quit and
  Force Quit.
- **Startup**: what starts by itself (LaunchAgents for your user and for all users, LaunchDaemons), with orphans: empty
  files, programs that are gone, uninstalled apps. Your user's orphaned agents can be disabled or moved to the Trash,
  after a confirmation; the ones in /Library need an administrator password and are only shown here.
- **Keyboard**: the apps intercepting keys right now, actively (every keystroke waits for them) or only listening, with
  the delay measured by macOS. No permissions needed.
- **Uninstall**: installed apps with size and last use; for each one, what it left in the Library (data, caches,
  preferences, containers, launch agents, including the vendor's folder). The app and the chosen leftovers go to the Trash, after a confirmation.
- **Mole**: if you have [Mole](https://github.com/tw93/Mole) (`brew install mole`), preview and clean with `mo clean`
  and maintenance with `mo optimize`, inside the app. Mole is a separate program (GPL-3.0): we call it, we don't bundle
  it.
- **Apple Intelligence** (experimental): tips written by the model on your Mac, offline.

The tools read nothing until you open them.

## Alerts

With thresholds you choose: high CPU, memory pressure, growing swap, disk almost full (under 15%), hot chip, an app
using too much, a runaway process (system ones included, for over 10 minutes). An alert fires once when the condition
lasts long enough, and comes back only after the value has dropped. Orphaned startup items, days of uptime and mild heat
never alert: they stay in the panel and the sentence. If you update from an earlier version, the new kinds start off;
turn them on in Settings › Alerts.

If you pick Cocaine's island, the alert goes to Cocaine through its `cocaine://alert` link and stays in its recent
alerts. Cocaine only shows it when you've been away from the Mac for at least 20 seconds, unless **AI alerts › When ›
Also at the Mac** is on in Cocaine, and not at all while alerts are paused or Flash is off. In those cases What's Going
On also posts a macOS notification, so nothing gets lost. Settings › Alerts tells you which case you're in and has two
tests: right away, and "while away" (it waits 25 seconds so you can step away).

## Install

```sh
brew install --cask gguidotz/tap/whats-going-on
```

Homebrew downloads the DMG from the release, copies the app to Applications and clears the quarantine flag (the app
isn't notarized), so there's no "Open Anyway" step. Update: `brew upgrade --cask whats-going-on`. Uninstall:
`brew uninstall --cask whats-going-on` (`--zap` also removes the preferences).

Or build from source: you need macOS 14+ and the command line tools (`xcode-select --install`); with Xcode installed the
Liquid Glass icon is compiled too.

```sh
git clone https://github.com/GGuidotz/whats-going-on.git
cd whats-going-on
./build.sh --install
```

The app asks for no privacy permissions: it only reads system counters. It checks for updates on its own (every 6 hours,
can be turned off) and Settings › Updates shows what's new and the command to update.

## Feedback

Settings › Feedback (or right-click the menu bar item › Send Feedback):

- **Report a Problem** or **Suggest an Idea** opens a GitHub issue with the version, macOS and Mac model filled in. This
  is the preferred channel; issues are public, so leave personal data out.
- **Write an Email** goes to giulioguidotz@yahoo.com, with the same details at the bottom.
- **Diagnostics** is a report to copy or save and attach. It lists the version, your Mac, which readings work, your
  settings and the latest alerts; no app names, files or addresses.

## Known limits

- Apple silicon temperatures come from undocumented IOKit functions (the same ones Stats uses). If a macOS update
  changes them, the Temperature row disappears instead of showing wrong numbers.
- Root processes can't be read through kernel calls without privileges (proc_pid_rusage returns -1). For CPU and
  duration the app uses `ps`, which macOS installs with the privileges to read them: it gives a moving average over about
  a minute. Memory, disk and energy of those processes stay out of the app list.
- Spotlight doesn't say how far indexing has got: it's inferred from the work of its processes.
- The keyboard tap delay is the one macOS reports; above one second it isn't shown, because on macOS 27 such values also
  appear for taps never measured. Who holds the Accessibility or Input Monitoring permission without using it lives in a
  protected database and isn't read.
- The Login Items list in System Settings needs an administrator password: the Startup tab shows the LaunchAgents and
  LaunchDaemons files and opens Login Items with a button.
- Whole-Mac power is only available where the SMC exposes it; per-app energy and adapter power flow only on Apple
  silicon.
- Per-app network comes from macOS's `nettop`, run only while the Apps tool is open.
- No fans: recent Macs don't need it, and controlling them would require administrator privileges.
- The app isn't notarized: no Apple Developer account. Published versions are signed with a stable local identity, so
  macOS remembers Full Disk Access across updates.
- The map doesn't read `/System` (the sealed system volume) or Time Machine snapshots: that space shows up as "Not
  visible".

## License

MIT. © 2026 GGuidotz.
