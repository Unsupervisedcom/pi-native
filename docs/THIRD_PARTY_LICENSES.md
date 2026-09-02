# Third-Party Licenses

This project (source code) is licensed under the MIT License — see `LICENSE` at the
repo root. Some bundled assets carry their own licenses, listed here.

## Maple Font (Maple Mono)

- Project: [subframe7536/maple-font](https://github.com/subframe7536/maple-font)
- License: **SIL Open Font License, Version 1.1 (OFL-1.1)**
- Used for: monospace/code/terminal text in the app UI.

The OFL permits bundling and redistributing the font as part of this application
(including in an open-source, MIT-licensed project) without relicensing the font
itself. The font **remains under OFL-1.1**, not MIT — the project's MIT license
covers this repository's source code and original assets only, not the font.

Key OFL-1.1 obligations we need to keep satisfied when bundling the font:

- Keep the font's own license text (`OFL.txt`) alongside the font files in this repo.
- Do not sell the font by itself, separate from this application.
- If we ever ship a *modified* build of the font, do not distribute it under the
  font's original (reserved) name — see the upstream `OFL.txt` for the exact Reserved
  Font Name clause before modifying/subsetting the font.

The upstream `OFL.txt` should be vendored alongside the font files once they're added
to the Xcode project (e.g. under `PiNative/Resources/Fonts/`), not just linked here.
