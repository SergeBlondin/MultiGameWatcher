# Multi-Game Watcher — Xcode setup

A step-by-step guide for getting `MultiGameWatcher.swift` running on your iPad.

## 1. Create the Xcode project

1. Open Xcode → **File → New → Project…**
2. Choose **iOS → App**. Click **Next**.
3. Fill in:
   - **Product Name:** `MultiGameWatcher`
   - **Interface:** `SwiftUI`
   - **Language:** `Swift`
   - **Storage:** `None`
   - Leave "Include Tests" unchecked.
4. Pick any folder to save the project.

## 2. Replace the template code

Xcode generated two files: `MultiGameWatcherApp.swift` and `ContentView.swift`.

1. Delete `MultiGameWatcherApp.swift` (right-click → Delete → Move to Trash).
2. Open `ContentView.swift`, select all, delete.
3. Paste the entire contents of `MultiGameWatcher.swift` into `ContentView.swift`.

That single file contains the `@main` app entry, the model, and all views.

## 3. Project settings

Select the project at the top of the file navigator, then the app target.

### General tab
- **Minimum Deployments:** iOS 16.0 (or 16.4 if you want Safari Web Inspector).
- **Supported Destinations:** iPad only (remove iPhone if present).
- **iPad Orientation:** check only **Landscape Left** and **Landscape Right**.

### Signing & Capabilities tab
- **Team:** pick your Apple Developer team from the dropdown.
- **Bundle Identifier:** something unique, e.g. `com.sergebl.multigamewatcher`.
- Signing should say "Automatically manage signing."

### Info tab (or Info.plist)
Nothing required. All broadcaster sites are HTTPS, so no App Transport Security exceptions are needed.

## 4. Build & run

1. Plug your iPad into your Mac (USB-C cable — wireless works too but is flakier for first install).
2. Trust the computer on the iPad if prompted.
3. In Xcode's run destination dropdown (top bar), pick your iPad.
4. Press **Cmd-R** (or click the Run triangle).
5. First time: the iPad will show a "Untrusted Developer" alert. Go to **Settings → General → VPN & Device Management**, tap your developer profile, and trust it. Re-run.

## 5. First-time use on the iPad

1. Tap the Sportsnet pane → sign in with your TV provider when the site prompts.
2. Tap the Bell pane → sign in. (TSN will inherit the Bell Media login because they share identity; no separate TSN sign-in needed.)
3. Tap any pane's "MUTED" badge to make it the audible pane. Tap another pane's badge to switch audio. Tap the currently-audible pane's badge again to mute everything.

Cookies persist across app launches (shared `WKWebsiteDataStore`), so you shouldn't need to re-login often.

## What the scaffold does and doesn't do

**Does:**
- 2×2 grid of WKWebView panes, one URL each, independently reloadable.
- Edit pencil icon on each pane to change its URL on the fly.
- Tap-to-switch audio via the MUTED/AUDIO badge in the top-right of each pane. Internally, it injects JavaScript into each web view that walks the DOM and sets `video.muted` on every media element.
- Shared cookie store across the four web views so Bell/TSN share one login.
- Safari Web Inspector support (iOS 16.4+): connect your iPad to a Mac, open Safari, Develop menu, pick the device, and inspect any of the four web views live.

**Doesn't (yet):**
- Persist custom URLs across app launches. (Swap `@Published` for `@AppStorage` when you want this — an easy follow-up.)
- Preset layouts ("Saturday hockey night" etc.).
- Picture-in-picture on backgrounding.
- Sync playback across panes.
- Any per-pane volume control (all-or-nothing per pane).
- Handle cross-origin iframes inside a broadcaster's page — if any broadcaster tucks its `<video>` element inside a cross-origin iframe (different subdomain, different site), the JS mute injection can't reach it. This is a DOM security rule. If you hit this for a specific broadcaster, the fix is per-broadcaster custom JS that clicks *their* mute button via a known CSS selector.

## Expected quirks and how to react

- **"Plays but no audio when I tap AUDIO"** — the broadcaster is rendering video inside a cross-origin iframe. Open Safari Web Inspector (see above), identify the iframe's origin, and either (a) find a CSS selector for the player's mute button and write a per-pane custom script, or (b) accept that you'll use the broadcaster's own mute button for that pane.
- **"Broadcaster redirects to its app"** — some sites detect iPad and try to deep-link into their native app. If this happens, override the user-agent. Add `wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"` in `AppModel.webView(for:)` right after creating the WKWebView. This tells the site "I am desktop Safari" and most will stop redirecting.
- **"Login gets dropped between sessions"** — swap `WKWebsiteDataStore.default()` for a non-persistent store? No, you want the default (persistent). If cookies still drop, it's the broadcaster's own session timeout, not a WKWebView issue.
- **"App crashes with 'unsupported URL'"** — you typed something that didn't parse as a URL. The code adds `https://` automatically if missing, but malformed input can still fail. Check the URL in a browser first.

## Next iterations (when the core works)

1. Persist custom URLs per pane with `@AppStorage`.
2. A preset menu: save/load four-URL bundles.
3. A "now audible" pulse animation on the green border for better visual feedback.
4. A "double-tap pane for fullscreen" gesture.
5. Picture-in-picture for the audible pane when you switch apps.
