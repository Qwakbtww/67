# LucidDash

An unofficial iPhone/iPad app for keeping an eye on your Lucid Trading prop accounts.
It isn't affiliated with Lucid Trading. Lucid's own dashboard is always the source of truth.

## What it does

- **Accounts tab.** Tracks each evaluation or funded account against its rules:
  - balance, today's P&L and total P&L
  - drawdown floor and the buffer above it (end-of-day trailing, per-trade trailing or static; it can stop trailing at a level you set)
  - profit-target progress, daily loss left and the consistency rule (best day as a share of total profit)
  - status badges: Active, At risk, Target hit, Breached
  - a balance vs. drawdown-floor chart, a daily P&L chart, win rate, profit factor, average win/loss, and a trade log grouped by CME trading day (6 PM–5 PM New York time)
- **Lucid Portal tab.** Lucid's own web dashboard inside the app. You sign in once and the login is kept. You set the address in Settings.
- **Import.** Bring trades in from a CSV export, such as Tradovate's *Reports → Performance → Download CSV*. Generic CSVs with Date / Symbol / Qty / P&L / Fees columns work too, and duplicates are skipped. You can also add trades by hand.

Lucid doesn't publish a public API. So the native dashboard works from the trades you import, and the Portal tab shows the live official numbers.

Rule presets (25K / 50K / 100K / 150K) are only starting points. Check your plan's current rules on Lucid's site and edit them for each account.

## Build & run

You need a Mac with Xcode 15 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you want to regenerate the project.

```sh
open LucidDash.xcodeproj         # project is committed
# or, after editing project.yml:
brew install xcodegen && xcodegen generate
```

1. Choose your Team under *Signing & Capabilities*. If the bundle ID `com.example.LucidDash` is taken, change it.
2. Pick your iPhone, or a simulator, and press Run.
3. In the app: **Accounts → +**, pick a preset, adjust the rules, then **⋯ → Import CSV**. Or tap *Load Demo Account* to look around first.

To get a CSV onto the phone, AirDrop it or save it to Files. The importer opens the system file picker.

## Layout

```
LucidDash/                 SwiftUI app (iOS 17+)
  App/                     entry point, tab bar
  Store/                   JSON persistence, settings
  Views/                   dashboard, charts, editor, portal (WKWebView)
Packages/LucidCore/        platform-independent logic + tests
  Sources/LucidCore/       models, RulesEngine, CSVImporter, sample data
  Tests/LucidCoreTests/
project.yml                XcodeGen spec
```

Run the logic tests on macOS or Linux:

```sh
cd Packages/LucidCore && swift test
```
