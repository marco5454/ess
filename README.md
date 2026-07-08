# Bishopric Tracker

A personal-use Flutter app for keeping track of ward members and callings, with full offline support.

---

## Disclaimer

**This is an independent, personal-use tool.** It is **not affiliated with,
endorsed by, sponsored by, or connected to The Church of Jesus Christ of
Latter-day Saints** in any way. The terms *"LDS"*, *"bishopric"*, *"ward"*,
*"calling"*, and similar ecclesiastical vocabulary are used descriptively to
reference the operator's own personal record-keeping context. All names,
marks, and trademarks referenced here remain the property of their respective
owners.

This app is provided **for a single user's personal organization only**. It
is not an official record-keeping system for any ward, branch, stake, or
congregation. **Do not use it as a replacement for the Church's official
systems** (LCR, ChurchofJesusChrist.org, etc.) or as an authoritative source
for calling status, membership, or ecclesiastical decisions.

The software is provided **"as is" without warranty of any kind**, express
or implied. The author accepts no responsibility for data loss, sync
failures, incorrect information, or any consequences arising from the use or
inability to use this software. See [`LICENSE`](./LICENSE) for the full text.

## Privacy & data

Member data you enter (names, contact info, callings, notes) is stored
locally on the device in an on-device SQLite database and synchronized to
the Supabase project configured for that build. **No data is sent to the
author or to any other third party** beyond that Supabase instance. Because
the operator of the app is also the operator of the Supabase project, they
alone are responsible for handling any personal data in accordance with the
privacy laws that apply to them (GDPR, CCPA, local statutes, etc.) and for
obtaining any required consent from the individuals whose information is
recorded.

## Features

- Members list with search, add, edit, and archive
- Callings tied to members, with a full state machine (selected → extended → accepted → sustained → set apart → active → released) and a per-calling event history
- Ward summary grouped by organization + "needs attention" tab
- Dashboard with counts per calling state
- **Fully offline-first**: local Drift/SQLite database, realtime sync when online, outbox queue for writes made while offline, automatic drain on reconnect
- Supabase auth + row-level security backend

## Development

Standard Flutter workflow:

```
flutter pub get
dart run build_runner build          # regenerate Drift schema code
flutter analyze
flutter run -d <device>
```

The Android build vendors the SQLite amalgamation source (see `third_party/sqlite/`) so it does not need to fetch prebuilt native libraries from the internet during compilation.

## License

Released under the [MIT License](./LICENSE) with the additional unaffiliation
notice described in that file.
