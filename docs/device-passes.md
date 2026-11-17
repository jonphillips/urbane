# Device passes & held gates

Jon's checklist: real-device passes owed by merged work, plus held ops steps. `NEXT_UP.md`'s **Owed** line
points here. The executor never reads this file; it only appends its own gate through `closeout`.

**Standing rule (schema deploy before TestFlight):** a build that adds a synced table or column, or first
writes one, goes out only after the change is imported to Development with `cktool` and the schema is
deployed to Production (jon-platform `docs/ios/persistence-and-sync.md` § Adding a synced table or column).

## Owed now

*(nothing yet)*
- **M1 S6:** Check transit ETA calculation and refresh for a real building on iPad. ([M1](milestones/M1-browse.md))

## Held

- **M1 · S7 sharing pass:** Wendy accepts the share on her own iPad, and each of us sees the other's
  reaction within a minute. Held until S7 merges.
