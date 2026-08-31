# Harbor iOS

A native SwiftUI Stremio client for iPhone and iPad — inspired by [Harbor](https://github.com/harborstremio/harbor), rebuilt from scratch for iOS. Sign in with your Stremio account, sync your library and addons, browse catalogs, rank streams, and play them.

**No media is hosted, indexed, or bundled.** This is a client for the open Stremio addon protocol — you bring your own addons and sources.

---

## Install on your iPhone (IPA)

Every push to `main` builds an **unsigned IPA** via GitHub Actions:

1. Open **https://github.com/hatemeditz/harbor-ios/actions**
2. Click the latest green **Build IPA** run
3. Scroll to **Artifacts** → download **Harbor-ipa** (a `.zip` containing `Harbor-unsigned.ipa`)
4. Unzip it on your PC

### Sideload with Sideloadly (Windows/Mac, free)

1. Download [Sideloadly](https://sideloadly.io) and install it
2. Connect your iPhone via USB (trust the computer if asked)
3. Drag `Harbor-unsigned.ipa` into Sideloadly
4. Enter your **Apple ID**, click **Start**
5. On the phone: **Settings → General → VPN & Device Management** → trust your Apple ID certificate
6. Launch Harbor

> Free Apple ID installs expire after **7 days** — re-sign by plugging in again (or use AltStore to auto-refresh over Wi-Fi). A paid Apple Developer account ($99/yr) removes the expiry.

### AltStore alternative

Install [AltServer](https://altstore.io), place the IPA in your phone's folder / drag onto AltServer icon, install, then refresh weekly from the AltStore app.

---

## First-run setup

1. **Sign in** with your Stremio account (email/password)
2. Your installed addons + library sync automatically (Continue Watching, watchlist)
3. Go to **Settings → Streaming & Debrid**
   - Paste your debrid API key(s): Real-Debrid, AllDebrid, Premiumize, Debrid-Link, TorBox
   - Tap **Install / Update Torrentio** — this embeds your keys into Torrentio so streams come back as direct HTTPS links that play natively
   - No debrid? You can still play any addon that returns direct HTTP/HLS links
4. Optional: open **Settings → TMDB**, get a free v3 API key from [themoviedb.org/settings/api](https://www.themoviedb.org/settings/api), then verify and save it
   - Unlocks weekly trends, provider charts, genre browsing, and curated Discover collections
   - The key is stored in iOS Keychain and is never included in analytics or crash reports
   - Harbor still works with Cinemeta when no TMDB key is configured
5. Browse → tap a title → **Play** → pick a ranked stream

**Top 10 Trending This Week** comes from TMDB's weekly trending endpoint. **Your Streaming** uses TMDB watch-provider discovery for the selected catalog region and opens separate Top 10 movie and series pages for Netflix, Disney+, Prime Video, Apple TV+, Max, and Hulu.

The interface uses a compact bottom tab bar on iPhone and a native sidebar with larger heroes, rails, cards, and grids on iPad.

## Feature status (v0.9)

| Area | Status |
|---|---|
| Stremio login (Keychain session) | ✅ |
| Library sync: Continue Watching, watchlist, progress write-back every 10s | ✅ |
| Watched flagging at ≥90% | ✅ |
| Responsive iPhone and iPad layouts | ✅ |
| Home rails from addon catalogs + TMDB weekly Top 10 | ✅ |
| TMDB provider pages, genre browse, and curated Discover rows | ✅ |
| Search (Cinemeta movies + series) | ✅ |
| Detail pages, season/episode browser | ✅ |
| Stream engine: parallel queries, parse → trust → score → rank | ✅ |
| VLC playback (MKV/HEVC/DTS/ASS), resume, next episode, speed control | ✅ |
| Addon manager: remove / add-by-URL / Torrentio+debrid installer | ✅ |

Not yet: Live TV/EPG, anime room, Trakt, casting, themes, PiP (VLC engine), torrent-direct P2P.

## Troubleshooting

- **"Untrusted developer"** — Settings → General → VPN & Device Management → trust cert.
- **App won't install in Sideloadly** — make sure iTunes/Apple Drivers are installed; try removing old "Harbor" app first.
- **Streams listed but not playable** (lock icon) — those are bare torrent hashes; install Torrentio with a debrid key so they resolve to HTTPS.
- **Playback fails on one source** — pick another ranked stream from the list.
- **7-day expiry** — normal for free signing; re-sign or go paid.

## Development

```bash
brew install xcodegen   # macOS only
xcodegen generate
pod install
open Harbor.xcworkspace
```

CI regenerates everything on each push — no Xcode project files are committed.

## Credits

- [Harbor](https://github.com/harborstremio/harbor) — design inspiration, MIT licensed
- [Stremio](https://www.stremio.com) — open addon ecosystem (not affiliated)
- [MobileVLCKit](https://code.videolan.org/videolan/VLCKit) — media engine
