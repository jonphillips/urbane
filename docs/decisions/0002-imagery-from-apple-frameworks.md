# ADR-0002: Imagery comes from Apple frameworks, and we store the recipe, not the picture

*Status: proposed — 2026-11-16*

## Context

What makes Urbane worth having is that you can browse it: buildings and blocks you can flip through,
not a pin and a "Street View" button. The old brief rightly ruled out automated collection of listing
photography. That leaves imagery we generate or choose ourselves.

## Decision

1. **Four sources, and only these:**
   - **Look Around snapshots** (`MKLookAroundSnapshotter`), requested with an `MKMapItem` so the
     scene faces the place, not just the coordinate. These give the facade, the corner, and each
     vignette stop.
   - **An angled 3D map snapshot** (`MKMapSnapshotter` with a pitched `MKMapCamera` and realistic
     elevation), taken from one house angle and distance so every postcard matches.
   - **One hero image per building**, chosen by one of us from the building's own site in the
     in-app browser (`WebExtractorKit`). It's a deliberate personal choice, never automatic.
   - **Our own photos** from visits.
2. **Store the recipe, not the picture**, for generated images. A synced `Vignette` row holds what is
   needed to regenerate the image: place name, coordinate, and the map item's identifier where there
   is one, plus a caption and an order. The rendered JPEG is a **local, unsynced cache**, regenerated
   on each device on demand. This keeps CloudKit records small (jon-platform § SQLiteData fails
   silently: the 1 MB record limit fails without an error) and means nothing scraped ever syncs.
3. **Chosen images sync**: the hero image and visit photos are `BLOB` columns, so they sync as
   `CKAsset`s. Downscale them to about 1600 px on the long edge before storing.
4. **No Google APIs.** Live Look Around (`LookAroundPreview`) and "Open in Maps" stay one tap away for
   wandering. They are an extra, not the main experience.

## Open (S1 answers on device)

- How reliably do `MKMapItem`-based scene requests **face the building** in NYC? If they often face
  the street instead, vignettes need a way to choose a different nearby scene, or a "this one's
  wrong" control.
- Do 3D snapshots of mid-block buildings in Williamsburg and LIC look good, or only landmarks? If they
  look flat, use the satellite or hybrid map style for the angled view instead.

## Resolved by S1 (Jon, iPad, 2026-11-16)

- **The angled view is realistic hybrid.** It uses `MKHybridMapConfiguration(elevationStyle: .realistic)` at one
  house camera: pitch 55°, 350 m, heading 30°. Jon's verdict was "realistic hybrid looks good" for
  mid-block Williamsburg and LIC buildings. Realistic standard was tried alongside it and isn't used.
- **Look Around facing is inconclusive, so S4 tried making it adjustable.** It was hard to tell whether
  `MKMapItem` scenes consistently face the building. See § Resolved by S4 for the outcome.
- **A building can exist without a map item.** 420 Kent Avenue found no match in S1. Any building
  search can't find gets a pin placed by hand: the address as typed, the pin's coordinate, and no map
  item identifier. Its Look Around is requested by coordinate. "Fix location" re-runs the search or
  moves the pin (M1 S2).

## Resolved by S4 (Jon, iPad, 2026-11-16)

- **Look Around views aren't adjustable.** `MKLookAroundSnapshotter` takes a scene, not a camera
  heading, and MapKit never reports where someone has moved or turned in the viewer. So adjusting can
  only change *which scene is requested*. S4 built both candidates for that: picking a nearby place,
  and tapping a point on a small map. On the iPad, Jon found it amounted to dropping pins and seeing
  what came back. It was dropped.
- **The recipe stays a map item or a coordinate.** The default request, by the building's own map item
  and then by coordinate, faced The Ashland's front door. When a still faces the wrong way, the
  fallback is to look: tapping any Look Around still opens the full-screen viewer to pan and walk
  around, and that isn't saved. A building vignette's place can still be changed, by searching for a
  different place, but there's no "fix this view" control.

## Consequences

- Images take a moment to appear on a new device while the cache fills. Show the map snapshot first;
  it's fastest.
- If Apple has no Look Around coverage for a block, that building gets only its 3D view and hero image.
- If S1 shows Look Around isn't good enough, this ADR is revisited before anything else is built. The
  whole product premise depends on it. (S1 passed with the adjustments above.)
