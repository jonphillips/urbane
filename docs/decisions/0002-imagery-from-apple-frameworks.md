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

## Consequences

- Images take a moment to appear on a new device while the cache fills. Show the map snapshot first;
  it's fastest.
- If Apple has no Look Around coverage for a block, that building gets only its 3D view and hero image.
- If S1 shows Look Around isn't good enough, this ADR is revisited before anything else is built. The
  whole product premise depends on it.
