# Musy

A minimal Spotify now-playing widget for macOS. It floats on the desktop with no
window chrome and no Dock icon, showing the album art, track title, album, artist,
and a live progress bar. The visual style is tuned for light wallpapers.

Built with native Swift and SwiftUI. Track info is read from Spotify over
AppleScript, and cover art is fetched from Spotify's public oEmbed endpoint, so no
API key or login is required.

## Features

- Transparent, borderless window that sits directly on the desktop
- Album art, title, album, and artist with smart truncation
- Live progress bar with elapsed and remaining time, interpolated between updates
- Artwork is cached per track, so revisiting a song is instant
- Remembers its position — drag it anywhere and it stays there across launches
- Runs as a background agent: no Dock icon, no menu bar item

## Requirements

- macOS 26 or later
- Spotify desktop app installed

## Build & Run

```bash
./build_app.sh   # produces Musy.app
open Musy.app
```

On first launch, macOS will ask for permission to control Spotify — approve it so
Musy can read the current track.

To launch it automatically on login, add `Musy.app` under
**System Settings → General → Login Items**.

## Usage

- **Move:** drag the widget anywhere; it remembers the position
- **Quit:** right-click the widget → **Quit Musy**

## Development

Run directly without bundling:

```bash
swiftc Musy.swift -o musy && ./musy
```

## How it works

A timer polls Spotify once per second via `osascript`, parsing the track name,
artist, album, URL, position, duration, and player state. A faster timer
interpolates the playback position locally so the progress bar stays smooth
between polls. When the track changes, Musy derives the track ID from the Spotify
URL and pulls the cover from `open.spotify.com/oembed`, caching it in memory.

## License

MIT
