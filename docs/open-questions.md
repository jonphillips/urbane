# Open questions & candidates

The architect's and Jon's scratch pad. **The executor never reads this file** (jon-platform ADR-0005).
Work becomes dispatchable only when a plan PR moves it into a milestone or effort.

## Decisions for Jon and Wendy

- **Move-in target.** It decides when M2 (Watch) starts: about 60 days before, since NYC rentals list
  30–60 days ahead of availability. Before then there's nothing to watch.
- **Neighborhood list.** The destinations (SoHo, Tribeca, West Village, LES) lean downtown, but three of
  the five starting neighborhoods are Brooklyn, Queens or the UWS. Worth adding one or two downtown
  Manhattan neighborhoods, even just to compare against?
- **Seed buildings.** 15–20, chosen by the two of you. Urbane doesn't suggest any.
- **Market-rate only.** Rent-stabilized leases require the unit to be your primary residence, which a
  pied-à-terre fails. Filter them out when adding buildings.

## Candidates (not planned)

- **M2 — Watch.** StreetEasy saved-building and saved-search alerts, with no server we host. Gmail
  filter → a label → a Google Apps Script on a timer (it runs as Jon, so no OAuth app and no 7-day
  token expiry) → extracts listings → publishes a small JSON feed → Urbane fetches it on launch and
  turns it into `listings` and `rentObservations` (ADR-0005 § M2 preview). Fallback with zero
  infrastructure: share a listing from the StreetEasy app into an Urbane share extension.
- **M3 — Choose.** Visit day: a map route through tour candidates, quick photos and notes on site, and
  a side-by-side comparison of the last two or three.
- **Building record checks.** NYC Open Data (HPD violations, DOB permits for construction next door, 311
  complaints, bedbug filings) per building. It's the kind of fact that rules a building out. A cheap
  read-only panel, if we get that far.
- **Apartment lines and stacks.** Only if the last two buildings have lines worth comparing.
- **MCP access** for staging chapters from a chat (jon-platform ADR-0007), if pasting gets tedious.
- **Urbane's accent color and app icon.** Part of S1's look, not a polish pass. Jon's call.

## Retirement

When the lease is signed: export everything (CloudSyncKit backup plus a readable export of chapters,
reactions and rents), stop TestFlight builds, and archive the repo.
