# Fonts

DM Sans is the Latin face, matching Android. DM Sans has no Cyrillic glyphs, so Russian text on
Android is drawn by Roboto. The same two families are committed here and registered with
`UIAppFonts`:

- `TruckoRig/Resources/Fonts/DMSans-Regular.ttf`
- `TruckoRig/Resources/Fonts/DMSans-Medium.ttf`
- `TruckoRig/Resources/Fonts/DMSans-SemiBold.ttf`
- `TruckoRig/Resources/Fonts/DMSans-Bold.ttf`
- `TruckoRig/Resources/Fonts/Roboto-Regular.ttf`
- `TruckoRig/Resources/Fonts/Roboto-Medium.ttf`
- `TruckoRig/Resources/Fonts/Roboto-Bold.ttf`

Licenses, committed next to the files:

- DM Sans — SIL Open Font License 1.1 (`DMSans-OFL.txt`)
- Roboto — Apache License 2.0 (`Roboto-LICENSE.txt`)

Roboto has no semibold master. The semibold cascade uses Roboto Medium, the same way Android's
extra-bold face aliases to bold. `AppFont` puts Roboto behind DM Sans, then the system font.
