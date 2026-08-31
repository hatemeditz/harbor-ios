# Harbor analytics and diagnostics

This document is the source of truth for Harbor's Firebase Analytics, Crashlytics, and Performance Monitoring integration. It describes analytics schema version `1` and was reviewed against the implementation on 2026-08-30.

Harbor analytics are anonymous, best-effort, and never part of a product decision path. If Firebase is unavailable, disabled, or not configured, every analytics API becomes a no-op and the rest of the app continues normally.

## Scope

Harbor deliberately tracks a small, high-signal contract rather than every possible interaction. The contract answers one primary question — **did the user successfully start watching something?** — plus the diagnostics needed to explain the answer:

- Users, retention, and sessions (from Firebase's automatic reporting)
- The playback funnel from content opened to 90% watched
- Stream-fetch success rate and latency
- Playback success rate, failure reasons, and startup latency
- Crash-free users and sessions by app version
- Search success and click-through

Authentication, home browsing, season/episode selection, subtitles, addon management, library actions, and settings changes are **intentionally not instrumented**. Adding them later is a schema-additive change; see [Adding or changing analytics](#adding-or-changing-analytics).

## Architecture

Harbor uses the official Firebase Apple SDK `12.17.0`, installed with Swift Package Manager from `project.yml`. The app target links `FirebaseAnalyticsCore`, `FirebaseCrashlytics`, and `FirebasePerformance`; MobileVLCKit remains managed by CocoaPods.

The analytics boundary is intentionally small:

- `Harbor/Core/Analytics/AnalyticsSchema.swift` owns fixed event names, fixed parameter names, per-event allowlists, error categories, trace names, and schema versioning.
- `Harbor/Core/Analytics/AnalyticsService.swift` is the only Firebase-facing service. It configures Firebase, applies the collection preference, validates and sanitizes values, sends events, records privacy-safe non-fatals, and creates bounded performance traces.
- `Harbor/Core/Analytics/PlaybackAnalyticsSession.swift` owns one playback attempt: startup timing, the one-shot 90% milestone, actual wall-clock playing time, and aggregated buffering.
- Feature code calls typed APIs such as `AnalyticsService.shared.log(.playbackStarted, parameters: ...)`. Feature code must not import Firebase or call `Analytics.logEvent` directly.

Every event is filtered against that event's parameter allowlist. Unknown parameters are dropped. String values must be short tokens containing only letters, numbers, `_`, `.`, or `-`; numeric values must be finite, nonnegative, and bounded. A `media_id` is sent only when it is a public IMDb-style identifier matching `tt` followed by digits. A `playback_session_id` must parse as a UUID.

Every event automatically includes:

| Parameter | Meaning |
| --- | --- |
| `analytics_schema_version` | Integer contract version, currently `1` |
| `build_environment` | `debug` or `release` |

In the event catalog, **playback context** means the following allowlisted parameters: `media_type`, `media_id`, `source`, `season_number`, `episode_number`, and `playback_session_id`. Values are included only when available. The session ID is a new random UUID for each playback attempt and is not an account, device, or person identifier.

Firebase continues to provide its standard app metrics when collection is active, including app-instance-based users, first opens, sessions, engagement, device model, OS version, app version, and approximate geography. Harbor does not emit a duplicate custom `app_open`; use Firebase's automatic `first_open`, `session_start`, and engagement reporting. See Firebase's [default data collection reference](https://support.google.com/firebase/answer/6318039).

Harbor emits **no** `screen_view` events. Automatic SwiftUI screen reporting is disabled, and the current screen is recorded only as a Crashlytics custom key so crash reports stay debuggable. Automatic Firebase Performance instrumentation is also disabled before Firebase configuration because private addon and debrid configuration can occur inside URL paths. Harbor uses category-only custom traces instead; no trace accepts a URL.

## Event catalog

Eighteen events. The parameters below are the complete per-event allowlists; all events also receive the two common parameters above.

### Search

| Event | Trigger | Parameters |
| --- | --- | --- |
| `search_submitted` | A debounced search request is issued | `query_length`, `search_scope` |
| `search_results_returned` | The request returned at least one result | `query_length`, `result_count`, `search_scope`, `search_duration_ms`, `result_type` |
| `search_no_results` | The request succeeded with zero results | `query_length`, `search_scope`, `search_duration_ms` |
| `search_failed` | The request failed | `query_length`, `search_scope`, `search_duration_ms`, `error_type` |
| `search_result_clicked` | A user opens a search result | `media_type`, `media_id`, `source`, `result_position`, `search_scope` |

The raw query string is never sent. `query_length` is a character count, `search_scope` is a fixed catalog-scope token, and `result_type` is a fixed response-status token.

### Content engagement

| Event | Trigger | Parameters |
| --- | --- | --- |
| `movie_opened` | A movie detail view appears | `media_type`, `media_id`, `source` |
| `series_opened` | A series detail view appears | `media_type`, `media_id`, `source` |

`source` is a fixed navigation origin: `home`, `search`, `watchlist`, `continue_watching`, `library`, or `unknown`. Titles are never sent; only a public IMDb-style `media_id` when one is available.

### Playback funnel

| Event | Trigger | Parameters |
| --- | --- | --- |
| `play_clicked` | The user taps Play, or an autoplay-next attempt begins | playback context |
| `stream_fetch_started` | The addon stream fan-out begins | playback context |
| `stream_fetch_success` | The complete addon fan-out produced at least one accepted/ranked stream | playback context, `stream_count`, `addon_count`, `addon_success_count`, `addon_failure_count`, `fetch_duration_ms` |
| `stream_fetch_failed` | No streams, or every addon failed | playback context, `stream_count`, `addon_count`, `addon_success_count`, `addon_failure_count`, `fetch_duration_ms`, `error_type` |
| `stream_selected` | A stream is chosen manually or automatically | playback context, `stream_position`, `quality`, `resolution`, `codec`, `container`, `stream_type`, `provider_type` |
| `playback_start_requested` | Harbor commits to a playback attempt; normally just before the player loads, or before an automatic-next selection failure | playback context |
| `playback_started` | VLC reaches the playing state | playback context, `playback_startup_ms`, `duration_bucket` |
| `playback_failed` | VLC errors, or automatic next-episode playback cannot obtain a playable URL | playback context, `playback_startup_ms`, `watch_time_seconds`, `error_type` |
| `playback_90` | 90% of the item has been reached, once per attempt | playback context, `duration_bucket`, `watch_time_seconds` |
| `playback_completed` | Playback reaches the end | playback context, `duration_bucket`, `watch_time_seconds` |
| `playback_stopped` | The player is dismissed or torn down | playback context, `duration_bucket`, `watch_time_seconds`, `progress_percent`, `buffer_count`, `total_buffer_seconds`, `stop_reason` |

Notes:

- `playback_startup_ms` is measured from `playback_start_requested` to the first playing state. On a failure that occurs *after* playback already started, the event carries the original startup time, not the time until failure.
- On `stream_fetch_success`, `fetch_duration_ms` and all stream/addon counters are emitted only after the complete addon fan-out finishes. A returned torrent hash can be ranked but not directly playable, so the later `stream_selected` step remains the correct playability signal.
- `watch_time_seconds` is accumulated wall-clock time in VLC's playing state. Seeking and resume offsets do not inflate it.
- Buffering is aggregated per attempt into `buffer_count` and `total_buffer_seconds` on `playback_stopped`. No per-buffer events are emitted.
- Resuming an item already past 90% suppresses the milestone so a resumed session cannot double-count it.
- `stop_reason` is one of `dismissed`, `ended`, `failed`, `replaced`, `unknown`.
- `stream_type` is a fixed transport classification derived from the selected stream: `http`, `https`, or `torrent`; it is omitted when Harbor cannot classify the transport reliably. `provider_type` is `official`, `third_party`, or `unknown`. Stream URLs, magnets, hashes, addon names, and stream titles are never sent.

## Error categories and Crashlytics

Analytics and custom traces use bounded error categories:

`network_error`, `timeout`, `offline`, `dns_error`, `cancelled`, `http_401`, `http_403`, `http_404`, `http_4xx`, `http_5xx`, `invalid_auth`, `invalid_url`, `decoding_error`, `server_error`, `no_addons`, `no_streams`, `all_addons_failed`, `vlc_error`, and `unknown`.

Important non-crashing failures are recorded as synthetic `NSError` instances with one of these fixed kinds:

- `stream_fetch_error`
- `playback_error`

The original `Error` is deliberately never passed to Crashlytics because an `NSError`, localized description, underlying response, or request can contain a URL, token, credential, or server-provided private text. A non-fatal contains only its fixed kind and category plus safe optional context: `screen`, `operation`, `media_type`, and `player_state`. Identical fingerprints are suppressed for 30 seconds to prevent error storms.

Crash reports also use safe custom keys `current_screen`, `current_operation`, `player_state`, and `media_type`. `current_screen` is one of `login`, `home`, `search`, `library`, `settings`, `detail`, `streams`, `player`, `addons`, `debrid_setup`; `current_operation` is `catalog`, `metadata`, `streams`, or `idle`.

Crashlytics supplies stack traces, affected users, app version, device, and OS. Crash-free users and crash-free sessions appear only after real sessions and crashes reach Firebase; see [Crashlytics setup](https://firebase.google.com/docs/crashlytics/ios/get-started), [custom report guidance](https://firebase.google.com/docs/crashlytics/ios/customize-crash-reports), and [crash-free metrics](https://firebase.google.com/docs/crashlytics/crash-free-metrics).

The XcodeGen target includes a conditional Crashlytics symbol-upload build phase. It invokes Firebase's SPM `Crashlytics/run` script only when both the built Firebase configuration and script exist. Missing configuration or an upload failure produces a warning and does not fail the unsigned archive. Release builds use dSYMs (`DEBUG_INFORMATION_FORMAT = dwarf-with-dsym`). Confirm a production crash only with a disposable test build; do not intentionally crash a build delivered to users.

## Performance Monitoring

Harbor starts only two fixed custom traces and stops each on success, failure, cancellation, or early termination:

| Trace | Measurement | Attributes / metrics |
| --- | --- | --- |
| `stream_fetch` | Whole addon stream fan-out | `media_type`, `outcome`, `error_category`; `success`, `stream_count`, `addon_count`, `failure_count` |
| `playback_start` | Player request to first playing state or terminal failure | `media_type`, `outcome`, `error_category`; `success` |

`HarborPerformanceTrace.stop` is idempotent, so a trace cannot be double-stopped or leaked when a flow both fails and is dismissed.

`Performance.sharedInstance().isInstrumentationEnabled` is set to `false` before Firebase starts. This is a deliberate privacy tradeoff: Harbor cannot safely allow automatic URL-based network traces while third-party addon/debrid secrets may be embedded in URL paths. It also means Firebase's automatic app-start and HTTP-request metrics are unavailable, so app-start regressions must be judged from Xcode Organizer or manual measurement instead. `isDataCollectionEnabled` still controls the manual traces. See Firebase's [collection controls](https://firebase.google.com/docs/perf-mon/disable-sdk) and [custom trace guidance](https://firebase.google.com/docs/perf-mon/custom-code-traces).

## Firebase project setup

1. Create or choose a Firebase project and enable Google Analytics. Do not enable Google Ads links or advertising features unless Harbor deliberately adopts them and the privacy/consent analysis is repeated.
2. In Firebase Console, add an Apple app with the exact bundle identifier `site.harbor.ios`.
3. Download that app's `GoogleService-Info.plist`. Do not rename or hand-edit it.
4. Put it at `Harbor/GoogleService-Info.plist`, then run:

   ```sh
   xcodegen generate
   pod install --repo-update
   xcodebuild -resolvePackageDependencies -workspace Harbor.xcworkspace -scheme Harbor
   ```

5. Open/build `Harbor.xcworkspace`, not only the generated project, because MobileVLCKit is supplied by CocoaPods.
6. In Analytics, review data-sharing, advertising-personalization, signal, retention, and product-linking settings. Keep advertising use disabled for the architecture documented here.
7. Give only necessary team members access to Firebase/Google Analytics and, if enabled, BigQuery.

Firebase describes its configuration plist as containing unique but non-secret project/app identifiers. It is technically safe to include under Firebase's normal model, but Harbor intentionally ignores `Harbor/GoogleService-Info*.plist` so forks and public unsigned builds are not tied to the owner's Firebase project. Obtain it only from Firebase Console; never invent project IDs or API values. See [Firebase Apple setup](https://firebase.google.com/docs/ios/setup) and [installation methods](https://firebase.google.com/docs/ios/installation-methods).

### CI and unsigned IPA builds

The build and release workflows keep working without a Firebase plist. In that case Firebase dependencies still compile, the dSYM phase skips safely, and `AnalyticsService.configure()` detects the missing configuration and leaves Analytics, Crashlytics, and Performance as no-ops. This preserves Harbor's public unsigned IPA build.

Both workflows already contain a `Restore Firebase configuration (optional)` step that runs before `xcodegen generate`. To make an owner-built IPA report to Firebase without committing the plist, add a GitHub Actions repository or environment secret named:

```
FIREBASE_GOOGLE_SERVICE_INFO_PLIST_BASE64
```

Create the single-line value locally without printing it into CI logs, for example on macOS:

```sh
base64 < Harbor/GoogleService-Info.plist | tr -d '\n'
```

If the secret is absent, the step logs `Firebase configuration not supplied; Harbor analytics will remain disabled` and the build continues unchanged.

Both workflows also select the newest installed Xcode 16.3 or later before building, because Firebase 12.15+ requires Swift tools 6.1. The selection is discovered at runtime rather than pinned to an image-specific path, so a runner-image refresh cannot break the IPA build; if no qualifying Xcode is present, the step logs a warning and continues with the default toolchain.

Treat repository secrets and Firebase Console access as configuration authority even though the client plist is not a server credential. Never place a Stremio auth key, debrid key, addon configuration URL, or other application secret in these workflows.

## Collection behavior, DebugView, and environments

The generated Info.plist initially disables Analytics, Crashlytics, and Performance collection. After Firebase is configured, Harbor applies the persisted `Share anonymous analytics` preference to all three products together. The setting is on by default for Release and can be revoked at any time in Settings; disabling it prevents future SDK collection. It does not retroactively delete already collected server data.

Debug builds collect nothing unless the process was launched with Firebase Debug Mode. This prevents normal local development and test runs from contaminating production reports. Debug builds still print concise console messages such as `[Analytics] playback_started`; Release builds do not print analytics events.

To validate events in Xcode:

1. Ensure a valid `Harbor/GoogleService-Info.plist` is present and regenerate the project.
2. Edit the Harbor scheme, choose **Run > Arguments**, and add `-FIRDebugEnabled` under **Arguments Passed On Launch**.
3. Run the Debug build on a simulator or device and keep `Share anonymous analytics` enabled.
4. Open **Firebase Console > Analytics > DebugView**, select the debug device, and exercise the flow. Confirm event names and parameters; also check the Xcode console for `[Analytics] ...` lines.
5. Remove `-FIRDebugEnabled` when finished, or launch with `-FIRDebugDisabled` to turn Firebase Debug Mode off.
6. In the linked GA4 property, create and test a developer-traffic filter if you need to keep debug-device traffic out of standard reporting.

DebugView is a real-time validation tool, not a separate analytics property. Do not assume debug traffic is automatically absent from normal reports or exports; use a separate Firebase development project for strict isolation, or configure and test an appropriate GA4 developer-traffic filter. Follow the current [DebugView instructions](https://firebase.google.com/docs/analytics/debugview) and [GA4 developer-traffic guidance](https://support.google.com/analytics/answer/13296662).

Harbor currently uses one Firebase app configuration. `build_environment` separates Debug and Release events, and Debug collection is opt-in as described above. Separate development and production Firebase projects give stronger data/access isolation, but require separate plist selection, build configurations, CI secrets, retention settings, and dashboards. Use that complexity only when Harbor has a sustained staging/release process; do not dynamically choose a project at runtime.

## Dashboards, explorations, and metrics

Firebase Analytics is backed by a linked Google Analytics 4 property. New data can take time to appear outside DebugView.

| Question | Where to look |
| --- | --- |
| Users, new/returning users, DAU/WAU/MAU | Firebase **Analytics dashboard** and GA4 **Reports > User** / user-stickiness cards |
| Retention (D1/D7/D30) | GA4 **Reports > Retention** or **Explore > Cohort exploration** |
| Sessions and average engagement/session duration | GA4 **Reports > Engagement** |
| Device model, iOS version, app version | GA4 **Reports > Tech > Tech details** |
| Country/region | GA4 **Reports > User attributes/Demographics**; geography is approximate |
| Event counts and parameters | Firebase **Analytics > Events**, GA4 **Reports > Engagement > Events**, or **Explore** |
| Funnels | GA4 **Explore > Funnel exploration** |
| Crashes, non-fatals, affected users, stack traces | Firebase **Release & Monitor > Crashlytics** |
| Crash-free users and sessions | Crashlytics dashboard / release monitoring |
| Stream-fetch and playback-start latency | Firebase **Release & Monitor > Performance > Custom traces** |
| Raw event-level joins | Firebase-to-BigQuery export, if explicitly enabled and governed |

References: [Analytics reports and BigQuery](https://firebase.google.com/docs/analytics/reports), [GA4 funnel explorations](https://support.google.com/analytics/answer/9327974), [user stickiness](https://support.google.com/analytics/answer/12993725), and [user metrics](https://support.google.com/analytics/answer/12253918).

### Recommended top-level dashboard

Keep the headline dashboard to ten numbers:

DAU/WAU/MAU · D1/D7/D30 retention · Successful Viewer Rate · Streams Found Rate · Playback Success Rate · median and P95 stream-fetch time · median and P95 playback-startup time · 90% Watch Rate · crash-free users · top playback failure categories by app version.

Everything else in this document is supporting diagnostic detail.

### Recommended funnel explorations

Use indirect steps unless validating an exact UI path, constrain the funnel to a sensible session/time window, and break down by `build_environment`, app version, `media_type`, and `source`.

1. Main playback: `movie_opened` **or** `series_opened` -> `play_clicked` -> `stream_fetch_success` -> `stream_selected` -> `playback_started` -> `playback_90`.
2. Search: `search_submitted` -> `search_results_returned` -> `search_result_clicked` -> `play_clicked`.

For attempt-level playback joins, export to BigQuery and join on `playback_session_id`. Do **not** register `playback_session_id` as a GA4 custom dimension; its high cardinality can degrade reports. Public `media_id` may also be high-cardinality and is better kept in BigQuery or narrowly filtered explorations.

### Recommended custom definitions

GA4 event parameters do not all become report dimensions automatically. Register only fields that will drive a maintained report.

- Event-scoped dimensions: `build_environment`, `media_type`, `source`, `search_scope`, `result_type`, `error_type`, `resolution`, `codec`, `container`, `stream_type`, `provider_type`, `duration_bucket`, and `stop_reason`.
- Event-scoped numeric metrics: `result_count`, `search_duration_ms`, `stream_count`, `addon_count`, `addon_success_count`, `addon_failure_count`, `fetch_duration_ms`, `stream_position`, `playback_startup_ms`, `watch_time_seconds`, `progress_percent`, `buffer_count`, and `total_buffer_seconds`.

Harbor sets no custom user properties, so there are no user-scoped definitions to register. Avoid registering identifiers or values with unbounded cardinality. Firebase/GA4 custom-definition quotas apply; see [GA4 custom dimensions and metrics](https://support.google.com/analytics/answer/14240153).

### Metric definitions

Keep numerator and denominator in the same date range, platform, app version, and population. For strict attempt-level ratios, deduplicate by `playback_session_id` in BigQuery.

| Metric | Definition |
| --- | --- |
| Successful Viewer Rate | Unique users with `playback_started` / active users |
| Play Click Rate | `play_clicked / (movie_opened + series_opened)` |
| Streams Found Rate | `stream_fetch_success / stream_fetch_started` |
| Playback Success Rate | `playback_started / playback_start_requested` |
| Playback Failure Rate | `playback_failed / playback_start_requested` |
| 90% Watch Rate | `playback_90 / playback_started` |
| Completion Rate | `playback_completed / playback_started` |
| Search Success Rate | `search_results_returned / search_submitted` |
| Search Click-Through Rate | `search_result_clicked / search_results_returned` |
| Average Stream Fetch Time | Average `fetch_duration_ms` on terminal stream-fetch events, or duration of the `stream_fetch` Performance trace |
| Average Playback Startup Time | Average `playback_startup_ms` on `playback_started` |
| Average Watch Time | Average `watch_time_seconds` on `playback_stopped` |
| Average Session Duration | Firebase/GA4 automatic session and engagement metrics |

Prefer medians and P95 over averages for latency once volume allows. Recommended saved reports: playback success and failure by app version and `error_type`; stream-fetch success and duration by `addon_count`; startup time by device, iOS version, and app version; 90% watch rate by `duration_bucket`, `media_type`, and `source`; search outcome and latency by `search_scope`; non-fatals by operation; crash-free users and sessions by release; retention cohorts by first-open week and app version.

## Privacy and prohibited data

Never send any of the following to Analytics, Crashlytics keys/logs/non-fatals, Performance trace names/attributes, or debug logging:

- Passwords, Stremio passwords, emails, usernames, user IDs, auth keys, session keys, access tokens, authorization headers, cookies, request bodies, or server response bodies.
- API keys, debrid keys/tokens, private subtitle keys, configured addon path segments, or any other credential.
- Full or partial private URLs, query strings, addon transport URLs, provider URLs, stream URLs, magnet links, torrent hashes/infohashes, torrent sources, or redirected URLs.
- Raw search terms, media titles, episode titles, release-group text, stream titles/descriptions, addon IDs/names/contacts, subtitle IDs/names/file paths/URLs, poster/background/avatar URLs, or free-form setting values.
- Raw `Error`/`NSError`, `localizedDescription`, HTTP body text, VLC diagnostic text, or any other free-form error message.
- Exact playback seek history or periodic progress events. Only the one-shot milestone and aggregate watch/buffer values are allowed.

Harbor never calls `Analytics.setUserID` and never maps a Stremio user ID, email address, username, or auth key to a Firebase user or user property.

If new code cannot prove that a value is a fixed safe token or bounded number, omit it. Sanitization is defense in depth, not permission to pass secrets into `AnalyticsService`.

## Consent and user control

Harbor includes a visible `Share anonymous analytics` toggle that controls Analytics, Crashlytics, and Performance together. It does not show a forced first-launch modal. There is no universal rule that a modal is always required solely because Firebase Analytics is present; the applicable legal basis depends on the publisher, markets, policy wording, enabled Firebase/Google product links, and use of identifiers/local storage.

Before distribution, publish a privacy policy that identifies Google/Firebase, explains the event and diagnostic categories in this document, states the purpose and retention, explains approximate geography and app-instance identifiers, and gives clear opt-out/revocation instructions. Google Analytics policy requires proper notice and either consent or an opportunity to opt out. For a market or legal assessment that requires prior opt-in, change the default collection preference to off for that population and obtain valid consent before enabling collection. Do not rely on this engineering document as legal advice.

Review [Google Analytics privacy guidance](https://support.google.com/analytics/answer/6004245), the [GA SDK/Measurement policy](https://developers.google.com/analytics/devguides/collection/protocol/ga4/policy), and, where applicable, Google's [EU user consent policy](https://www.google.com/about/company/user-consent-policy/). Record consent where legally required and make revocation as easy as granting it.

### ATT and advertising

Harbor does not use Firebase for advertising, does not link events to third-party data for advertising or measurement, does not set a Firebase User ID, does not import/request IDFA in app code, and does not request App Tracking Transparency permission. The target links `FirebaseAnalyticsCore`, the variant without the IDFA-collecting AdSupport linkage. Its generated Info.plist also disables Apple ad-network attribution registration and personalized-ad signals with `GOOGLE_ANALYTICS_REGISTRATION_WITH_AD_NETWORK_ENABLED = NO` and `GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS = NO`. The current design therefore does not add `NSUserTrackingUsageDescription` or an ATT prompt.

Firebase Analytics always creates a resettable app-instance identifier. An app-instance or vendor identifier used only for Harbor's first-party analytics is not by itself Apple's cross-company "tracking." Reassess ATT **before** adding ads, remarketing, cross-app/cross-company profile linking, sharing with a data broker, advertising measurement, Google advertising features, or code that accesses IDFA. If any such tracking is added, obtain ATT authorization before tracking or accessing the advertising identifier and update App Privacy disclosures. See Apple's [user privacy and data use guidance](https://developer.apple.com/app-store/user-privacy-and-data-use/) and Firebase's [identifier behavior](https://support.google.com/firebase/answer/6318039).

## App Store Connect App Privacy review

Apple requires the publisher to describe its own collection and every integrated third party. Firebase's privacy manifests cover SDK behavior but do not answer App Store Connect for the app. Before each submission, generate/review Xcode's privacy report from the exact archive, list every resolved Firebase target, compare it with Firebase's current [App Store data-collection guide](https://firebase.google.com/docs/ios/app-store-data-collection), and audit Harbor's non-Firebase Stremio/addon behavior separately. Apple says disclosures must remain accurate when behavior changes; see [App privacy details](https://developer.apple.com/app-store/app-privacy-details/) and [privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files).

For the exact analytics implementation documented here, review and disclose these categories in App Store Connect:

| Apple data type | What Harbor/Firebase sends | Purpose | Tracking |
| --- | --- | --- | --- |
| Device ID | Firebase app-instance identifier; vendor identifier behavior depends on SDK linkage and availability | Analytics | No under the current no-ads/no-cross-app design |
| Product Interaction | Content opens, search result clicks, and the play/stream/playback funnel including the 90% milestone | Analytics | No |
| Search History | A search occurred, query length/scope/outcome/count, and clicked public media ID; **not** the raw query | Analytics | No |
| Coarse Location | Approximate country/region derived by Google; Firebase Performance documents IP use for geographic segmentation | Analytics / App Functionality | No |
| Crash Data | Crash stack traces and relevant application state | App Functionality / Analytics | No |
| Performance Data | Stream-fetch and playback-start custom traces, plus Firebase-documented SDK performance data | App Functionality / Analytics | No |
| Other Diagnostic Data | Bounded non-fatal categories/context, playback error categories, aggregate buffering, SDK transport-quality metadata | App Functionality / Analytics | No |
| Other Usage Data | Sessions/lifecycle and device/OS/app metadata not better represented above | Analytics | No |

Do not declare Email Address or User ID **for this Firebase integration**: Harbor never sends them to Firebase. The app itself does send the user's email and password directly to Stremio for login and syncs library data with Stremio, so the publisher must separately evaluate those first-party/third-party service flows for the app's complete privacy label.

For "Data Linked to You," do not guess from this table. Harbor does not set Firebase User ID or transmit an account identifier, but Analytics associates events with a resettable app-instance/device identifier and an owner could change linkage through BigQuery or other product links. Answer from the exact archive, Firebase privacy manifests, console links/data-sharing settings, backend/export practices, and Apple's current definition. Under no circumstances mark these analytics data as used for tracking unless the product behavior is changed to meet Apple's tracking definition.

## Verification status

The unchanged base revision `c800ca0` completed both the [Build IPA workflow](https://github.com/hatemeditz/harbor-ios/actions/runs/32900755551) and [Release IPA workflow](https://github.com/hatemeditz/harbor-ios/actions/runs/32901829755) successfully. For this implementation, `project.yml` and both workflow YAML files parse successfully, both workflows pass `actionlint` 1.7.12, `git diff --check` passes, the schema tests cover the fixed event contract and sensitive-field exclusions, and Firebase calls are centralized in `AnalyticsService`.

This checkout is currently on Windows and has no Xcode, XcodeGen, CocoaPods, Swift compiler, iOS simulator, or MobileVLCKit runtime. Therefore the modified app has **not yet** received a macOS compile/test/archive run, a real-device VLC playback test, a Firebase DebugView delivery test, or a deliberate disposable-build Crashlytics test. Run the Build IPA workflow (with the optional Firebase secret for delivery checks) before merging or releasing; a successful changed-revision run is the authoritative XcodeGen, SwiftPM, CocoaPods, test, unsigned archive, and IPA-package verification.

## Adding or changing analytics

1. Add a fixed snake_case event or parameter case in `AnalyticsSchema.swift`; never construct event names dynamically.
2. Add the minimum parameter allowlist for that event. Prefer a bucket/category over an identifier and omit anything that could contain user or third-party text.
3. Update the expected event set in `HarborTests/AnalyticsTests.swift`. That test fails on any unintentional contract change, which is the point.
4. Call `AnalyticsService`, not Firebase, at a meaningful user action or terminal operation outcome. Analytics must not block `async` work or the main thread.
5. For timers/traces, cover success, error, cancellation, and early-return paths. `HarborPerformanceTrace.stop` is idempotent.
6. For playback progress, use one-shot milestones or an end-of-session aggregate. Never emit periodic analytics.
7. Categorize errors before the analytics boundary. Never pass the original error or URL.
8. Update the event tables here and validate in DebugView.
9. Increment `HarborAnalyticsSchema.version` only for an incompatible meaning/parameter change. Additive events can remain in the current version when existing semantics do not change.
10. Re-run the App Store privacy, consent, ATT, GA custom-definition, BigQuery, and data-retention reviews whenever collection changes.
