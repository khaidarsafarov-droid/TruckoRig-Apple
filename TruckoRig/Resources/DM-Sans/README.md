# DM Sans

The app's type scale is DM Sans. The font files are **not** committed here: DM Sans is under the
SIL Open Font License and is better fetched than vendored into an app repository.

## Adding the font

1. Download DM Sans from [Google Fonts](https://fonts.google.com/specimen/DM+Sans).
2. Copy these three files into this folder:
   - `DMSans-Regular.ttf`
   - `DMSans-Medium.ttf`
   - `DMSans-Bold.ttf`
3. Regenerate the project so the new files become target members:
   `python3 Tools/generate_xcodeproj.py`
4. `Info.plist` already lists all three under `UIAppFonts`.

## If you skip this

Nothing breaks. `AppFont` checks whether each face is registered at runtime and falls back to the
system font at the same size and weight, and Settings → About shows a note saying the fallback is
in use. The layout is unchanged either way.
