# Device passes & held gates

Jon's checklist: real-device passes owed by merged work, plus held ops steps. `NEXT_UP.md`'s **Owed** line
points here. The executor never reads this file; it only appends its own gate through `closeout`.

**Standing rule (schema deploy before TestFlight):** a build that adds a synced table or column, or first
writes one, goes out only after the change is imported to Development with `cktool` and the schema is
deployed to Production (jon-platform `docs/ios/persistence-and-sync.md` § Adding a synced table or column).

## Owed now

- **M1 S7d:** On 420 Kent, Extract rents offers #1009, #802, and #560 on the 2 beds tab; the Studio tab still recommends tapping 2 beds. ([M1](milestones/M1-browse.md))
- **M1 S7e:** On iPad, enable Satellite 3D over Midtown; confirm the map tilts to realistic 3D, building markers and neighborhood labels remain, stations appear when zoomed in, and turning it off leaves the camera in place. ([M1](milestones/M1-browse.md))
- **M1 S7f:** On iPad landscape, tap three markers in sequence; verify the panel swaps, closing restores map controls, Capture rents is page-sized, Edit links and Fix location save, the postcard opens full-screen, and website and review links open in Safari. On iPhone, verify marker taps still show the sheet. ([M1](milestones/M1-browse.md))

## Held

- **M1 · S8b sharing pass:** Wendy accepts the share on her own iPad, and each of us sees the other's
  reaction within a minute. Held until S8b merges and the [PROD-CUTOVER](PROD-CUTOVER.md) steps are done.
