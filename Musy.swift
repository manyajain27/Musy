// musy — little spotify now playing widget that floats on the desktop
// build: ./build_app.sh   (or swiftc Musy.swift -o musy && ./musy)
// drag to move, right click to quit

import SwiftUI
import AppKit
import Combine

@MainActor
final class PlayerModel: ObservableObject {
    @Published var title    = ""
    @Published var album    = ""
    @Published var artist   = ""
    @Published var artwork: NSImage?
    @Published var isClosed = true
    @Published var isPlaying = false
    @Published var duration: Double = 0
    @Published var displayElapsed: Double = 0

    private var position: Double = 0
    private var posTimestamp = Date()
    private var currentURI: String?
    private var artCache: [String: NSImage] = [:]   // keep art around so revisiting a song is instant

    private var pollTimer: Timer?
    private var renderTimer: Timer?
    private let scriptQueue = DispatchQueue(label: "musy.applescript")

    var fraction: Double { duration > 0 ? min(1, max(0, displayElapsed / duration)) : 0 }
    var elapsedString: String   { Self.fmt(displayElapsed) }
    var remainingString: String { "-" + Self.fmt(max(0, duration - displayElapsed)) }

    init() {
        // ask spotify once a second, but tick the bar way faster so it looks smooth
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        renderTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        poll()
    }

    // fake the position forward between polls instead of waiting on spotify
    private func tick() {
        guard !isClosed, duration > 0 else { displayElapsed = 0; return }
        let e = isPlaying ? position + Date().timeIntervalSince(posTimestamp) : position
        displayElapsed = min(e, duration)
    }

    // one liner if spotify is dead, otherwise dump everything split by ~|~
    nonisolated static let script = """
    tell application "System Events" to set ok to (name of processes) contains "Spotify"
    if not ok then return "CLOSED"
    tell application "Spotify"
        return (name of current track) & "~|~" & (artist of current track) & "~|~" & (album of current track) & "~|~" & (spotify url of current track) & "~|~" & (player position as string) & "~|~" & (duration of current track as string) & "~|~" & (player state as string)
    end tell
    """

    private func poll() {
        scriptQueue.async { [weak self] in
            let out = Self.runAppleScript(Self.script)
            Task { @MainActor in self?.apply(out) }
        }
    }

    nonisolated private static func runAppleScript(_ src: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", src]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func apply(_ out: String?) {
        guard let out, out != "CLOSED", out.contains("~|~") else {
            showClosed(); return
        }
        let parts = out.components(separatedBy: "~|~")
        guard parts.count >= 7,
              let pos = Double(parts[4].trimmingCharacters(in: .whitespaces)),
              var dur = Double(parts[5].trimmingCharacters(in: .whitespaces))
        else { showClosed(); return }

        if dur > 3600 { dur /= 1000 }   // spotify hands back ms here, want seconds

        title  = parts[0]
        artist = parts[1]
        album  = parts[2]
        let uri = parts[3]
        duration = dur
        position = pos
        posTimestamp = Date()
        isPlaying = parts[6].lowercased().contains("playing")
        isClosed = false

        // only hit the network when the song actually changed
        if uri != currentURI {
            currentURI = uri
            fetchArtwork(trackID: String(uri.split(separator: ":").last ?? ""))
        }
    }

    private func showClosed() {
        guard !isClosed else { return }
        isClosed = true; isPlaying = false
        currentURI = nil; artwork = nil
        title = ""; album = ""; artist = ""
    }

    // no api key needed, oembed gives us the cover for free
    private func fetchArtwork(trackID: String) {
        guard !trackID.isEmpty else { return }
        if let cached = artCache[trackID] { artwork = cached; return }

        let oembed = "https://open.spotify.com/oembed?url=https://open.spotify.com/track/\(trackID)"
        guard let url = URL(string: oembed) else { return }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let thumb = obj["thumbnail_url"] as? String,
                  let turl = URL(string: thumb) else { return }
            var ireq = URLRequest(url: turl)
            ireq.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: ireq) { [weak self] idata, _, _ in
                guard let idata else { return }
                Task { @MainActor [weak self] in
                    // bail if the song already moved on while this was downloading
                    guard let self, let img = NSImage(data: idata) else { return }
                    self.artCache[trackID] = img
                    if self.currentURI?.hasSuffix(trackID) == true { self.artwork = img }
                }
            }.resume()
        }.resume()
    }

    nonisolated private static func fmt(_ sec: Double) -> String {
        let s = max(0, Int(sec))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}

struct MusyView: View {
    @ObservedObject var model: PlayerModel

    private let artSize: CGFloat = 132
    private let cardWidth: CGFloat = 296

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            artwork
            metadata
            progress
                .opacity(!model.isClosed && model.duration > 0 ? 1 : 0)
        }
        .padding(20)
        .frame(width: cardWidth, alignment: .leading)
        .contextMenu {
            Button("Quit Musy") { NSApp.terminate(nil) }
        }
    }

    private var artwork: some View {
        ZStack {
            if let img = model.artwork {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.black.opacity(0.06))
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(.black.opacity(0.35))
                    )
            }
        }
        .frame(width: artSize, height: artSize)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.black.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 5)
    }

    // black text + a soft white glow behind it, reads fine on a light wallpaper
    private var metadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            if model.isClosed {
                Text("Spotify is closed")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.8))
            } else {
                Text(model.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .lineLimit(1).truncationMode(.tail)
                Text(model.album)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.black.opacity(0.72))
                    .lineLimit(1).truncationMode(.tail)
                Text(model.artist)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.black.opacity(0.55))
                    .lineLimit(1).truncationMode(.tail)
            }
        }
        .shadow(color: .white.opacity(0.5), radius: 1.5, x: 0, y: 0.5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progress: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.2))
                    Capsule()
                        .fill(model.isPlaying ? .black : .black.opacity(0.5))   // dim it when paused
                        .frame(width: geo.size.width * model.fraction)
                }
            }
            .frame(height: 4)

            HStack {
                Text(model.elapsedString)
                Spacer()
                Text(model.remainingString)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.black.opacity(0.65))
            .shadow(color: .white.opacity(0.5), radius: 2)
        }
        .frame(height: 26)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let model = PlayerModel()

    func applicationDidFinishLaunching(_ note: Notification) {
        let hosting = NSHostingView(rootView: MusyView(model: model))

        window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false   // os shadow drew a weird double outline, art has its own
        // sit on the wallpaper behind every app window instead of floating on top
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.setContentSize(hosting.fittingSize)

        // remember wherever i dragged it last, only default to bottom right on first run
        let autosave = "MusyWidgetFrame"
        if !window.setFrameUsingName(autosave), let vf = NSScreen.main?.visibleFrame {
            let s = window.frame.size
            window.setFrameOrigin(NSPoint(x: vf.maxX - s.width - 40, y: vf.minY + 40))
        }
        window.setFrameAutosaveName(autosave)

        window.makeKeyAndOrderFront(nil)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // no dock icon, no menu bar, just the widget
    app.run()
}
