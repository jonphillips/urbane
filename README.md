# Urbane

Private iPad-first apartment search for Jon and Wendy. See [docs/README.md](docs/README.md)
for the product, decisions, milestones, and verification gate.

## Build

Requires Xcode 27, XcodeGen, and SwiftLint. Generate the project with
`xcodegen generate`, then open `Urbane.xcodeproj` or run `scripts/check-drift.sh`.
Enable the tracked SwiftLint hook in this clone with `git config core.hooksPath .githooks`.
