# What's Going On

What's happening on your Mac, in one sentence. [Italiano](README.md)

What's Going On lives in the macOS menu bar and shows CPU, memory and network in very little space: for each reading a
small label stacked one letter under the other, and the value next to it, colored from green to red as the load rises. Network has two lines,
upload and download, each in its own color. Open the panel and the top line tells you the one thing that matters right
now: "All quiet", or "Google Chrome is using 180% CPU for 4 min". Below it, a card per reading with a live graph; click
one for details.

It's a companion to [Cocaine](https://github.com/Mattiakart/cocaine): alerts can show up in its island. Independent
project, not affiliated with Cocaine. Inspired by [Stats](https://mac-stats.com).

## What it shows

| Reading | Details |
|---|---|
| CPU | user and system, per-core load (advanced mode), busiest apps |
| Memory | pressure, app, wired, compressed, swap, apps using the most memory |
| Network | download and upload speed, traffic since launch, local address |
| Temperature | chip and GPU; every sensor in advanced mode |
| GPU | usage and memory (advanced mode) |
| Disk | free space, reads and writes |
| Battery and power | level, time left, health, cycles, watts; whole-Mac power where macOS exposes it |

By default the menu bar shows CPU, RAM and NET. In Settings › Menu Bar you pick readings, order and style (numbers, or
numbers with a tiny bar graph), with a preview on light and dark menu bars. Right-click the item for settings, what's
new, feedback and quit.

On macOS 26 and later the panel, tabs and buttons use Liquid Glass, and the app icon is a layered Liquid Glass icon
(Icon Composer). On macOS 14 and 15 the same elements use the system materials.

## Alerts

With thresholds you choose: high CPU, memory pressure, disk almost full, hot chip, an app using too much. An alert fires
once when the condition lasts long enough, and comes back only after the value has dropped.

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
- System processes running as root can't be read without privileges, so they don't appear among the apps.
- Whole-Mac power is only available where the SMC exposes it.
- No fans: recent Macs don't need it, and controlling them would require administrator privileges.
- The app is ad-hoc signed and not notarized: no Apple Developer account.

## License

MIT. © 2026 GGuidotz.
