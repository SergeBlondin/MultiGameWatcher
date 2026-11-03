//
//  MultiGameWatcher.swift
//  A 2×2 iPad viewer for mixed live streams with tap-to-switch audio.
//
//  Paste this entire file into a new Xcode iOS/iPadOS App project, replacing
//  the template ContentView.swift. See SETUP.md for project settings.
//
//  Minimum deployment: iOS 16.0 (iOS 16.4 enables Safari Web Inspector).
//

import SwiftUI
import WebKit

// MARK: - App entry point

@main
struct MultiGameWatcherApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}

// MARK: - Model

struct StreamConfig: Identifiable, Equatable {
    let id: Int
    var label: String
    var url: URL?
}

/// Owns the four WKWebView instances. WKWebViews are reference types and must
/// persist across SwiftUI view rebuilds, so we keep them out of `@Published`
/// state and hand them to the UIViewRepresentable on demand.
final class AppModel: ObservableObject {
    @Published var streams: [StreamConfig] = [
        .init(id: 0, label: "YouTube",   url: URL(string: "https://www.youtube.com/live/jfKfPfyJRdk")),
        .init(id: 1, label: "Sportsnet", url: URL(string: "https://www.sportsnet.ca/live/")),
        .init(id: 2, label: "Bell",      url: URL(string: "https://tv.bell.ca/")),
        .init(id: 3, label: "TSN",       url: URL(string: "https://www.tsn.ca/live")),
    ]

    /// -1 means no pane is audible (everything muted).
    @Published var activeAudio: Int = -1

    /// Persistent reference to each pane's WKWebView. Not published.
    private var webViews: [Int: WKWebView] = [:]

    /// Shared data store: a login to Bell in one pane becomes available to TSN
    /// in another (they share Bell Media identity).
    private let sharedDataStore = WKWebsiteDataStore.default()

    func webView(for paneId: Int) -> WKWebView {
        if let existing = webViews[paneId] { return existing }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = sharedDataStore
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.allowsBackForwardNavigationGestures = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.backgroundColor = .black
        wv.isOpaque = false
        if #available(iOS 16.4, *) {
            wv.isInspectable = true  // Safari > Develop > [your iPad] to inspect
        }

        webViews[paneId] = wv
        if let url = streams[paneId].url {
            wv.load(URLRequest(url: url))
        }
        return wv
    }

    func reload(paneId: Int) {
        let wv = webView(for: paneId)
        if let url = streams[paneId].url {
            wv.load(URLRequest(url: url))
        }
    }

    func updateURL(_ newURL: URL, paneId: Int) {
        streams[paneId].url = newURL
        reload(paneId: paneId)
    }

    // MARK: Audio

    /// Walks the DOM (including same-origin iframes) of the given pane's WKWebView
    /// and sets the `muted` property on every <video>/<audio> element.
    /// Cross-origin iframe contents are unreachable; that's a DOM security rule.
    func setMuted(_ muted: Bool, paneId: Int) {
        guard let wv = webViews[paneId] else { return }
        let flag = muted ? "true" : "false"
        let js = """
        (function(){
          function walk(doc){
            try {
              doc.querySelectorAll('video,audio').forEach(function(m){ m.muted = \(flag); });
              doc.querySelectorAll('iframe').forEach(function(f){
                try { if (f.contentDocument) walk(f.contentDocument); } catch(e) {}
              });
            } catch(e) {}
          }
          walk(document);
        })();
        """
        wv.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Toggle audio on the given pane. Mutes every other pane.
    func activate(paneId: Int) {
        if activeAudio == paneId {
            setMuted(true, paneId: paneId)
            activeAudio = -1
            return
        }
        for i in streams.indices { setMuted(true, paneId: i) }
        setMuted(false, paneId: paneId)
        activeAudio = paneId
    }
}

// MARK: - SwiftUI ↔ WKWebView bridge

struct WebPane: UIViewRepresentable {
    @EnvironmentObject var model: AppModel
    let paneId: Int

    func makeUIView(context: Context) -> WKWebView {
        model.webView(for: paneId)
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No-op: URL changes are driven by AppModel.reload(paneId:).
    }
}

// MARK: - Pane view

struct PaneView: View {
    @EnvironmentObject var model: AppModel
    let paneId: Int

    @State private var editing = false
    @State private var urlText = ""

    private var stream: StreamConfig { model.streams[paneId] }
    private var isAudio:   Bool       { model.activeAudio == paneId }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .topTrailing) {
                WebPane(paneId: paneId).background(Color.black)
                audioBadge
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isAudio ? Color.green : Color.white.opacity(0.08),
                              lineWidth: 2)
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("\(paneId + 1) · \(stream.label)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.blue.opacity(0.9))
                .lineLimit(1)

            if editing {
                TextField("URL", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption2.monospaced())
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(applyUrl)
                Button("Go", action: applyUrl)
                    .font(.caption.weight(.semibold))
            } else {
                Text(stream.url?.host ?? "—")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    urlText = stream.url?.absoluteString ?? ""
                    editing = true
                } label: { Image(systemName: "pencil") }
                Button {
                    model.reload(paneId: paneId)
                } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.85))
        .font(.caption)
    }

    private var audioBadge: some View {
        Button(action: { model.activate(paneId: paneId) }) {
            HStack(spacing: 4) {
                Image(systemName: isAudio ? "speaker.wave.2.fill" : "speaker.slash.fill")
                Text(isAudio ? "AUDIO" : "MUTED")
            }
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isAudio ? Color.green : Color.black.opacity(0.75))
            .foregroundStyle(isAudio ? .black : .white)
            .clipShape(Capsule())
        }
        .padding(8)
    }

    private func applyUrl() {
        var candidate = urlText.trimmingCharacters(in: .whitespaces)
        if !candidate.contains("://") { candidate = "https://" + candidate }
        if let url = URL(string: candidate) { model.updateURL(url, paneId: paneId) }
        editing = false
    }
}

// MARK: - Root content view

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        GeometryReader { geo in
            let cellW = (geo.size.width  - 12) / 2
            let cellH = (geo.size.height - 12) / 2
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    PaneView(paneId: 0).frame(width: cellW, height: cellH)
                    PaneView(paneId: 1).frame(width: cellW, height: cellH)
                }
                HStack(spacing: 4) {
                    PaneView(paneId: 2).frame(width: cellW, height: cellH)
                    PaneView(paneId: 3).frame(width: cellW, height: cellH)
                }
            }
            .padding(4)
            .frame(width: geo.size.width, height: geo.size.height)
            .background(Color.black)
        }
        .environmentObject(model)
        .ignoresSafeArea()
    }
}
