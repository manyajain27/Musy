# Musy

A small Spotify now-playing widget for macOS. It sits on the desktop and shows
the album art, track, and a progress bar for whatever's playing.

Native Swift/SwiftUI. Reads the track from Spotify via AppleScript and grabs the
cover from Spotify's public oEmbed endpoint — no API key or login.

## Build & run

```bash
./build_app.sh   # builds Musy.app
open Musy.app
```

First launch asks for permission to control Spotify — allow it. To start it on
login, add `Musy.app` under System Settings → General → Login Items.

## Notes

- Drag to move (it remembers the position).
- Menu bar icon (or right-click the widget) toggles light/dark text and quits.
- Needs macOS 26 and the Spotify desktop app.
