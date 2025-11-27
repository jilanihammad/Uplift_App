iOS Launch Checklist (Flutter + Python backend on GCP)
0) Accounts & access

Enroll in Apple Developer Program (Company/Organization account recommended).

Add teammates in App Store Connect (Admin/Developer/App Manager as needed).

Create an App-Specific Password for Transporter (if you’ll use it).

1) Create the iOS app shell

In App Store Connect → “My Apps” → New App

Name, primary language, Bundle ID (must match Xcode), SKU, iOS platform.

Choose the bundle id you’ll set in Flutter/Xcode (reverse-DNS style, e.g., com.yourco.maya).

Set up App Privacy: “Privacy Nutrition Labels” (declare collection & usage of data: microphone audio, analytics, crash logs, account identifiers, etc.).

Add Privacy Policy URL and Terms URL (must be publicly accessible).

2) Configure the Flutter iOS project

In Flutter project:

flutter config --enable-ios (usually already on).

flutter build ios --release (first run will generate iOS project and install pods).

Open Xcode workspace: ios/Runner.xcworkspace.

In Xcode (Runner target):

General → Display Name, Version (e.g., 1.0.0), Build (e.g., 1).

Signing & Capabilities → Team, automatic signing ON, Bundle Identifier matches App Store Connect.

Deployment target (e.g., iOS 15.0+ unless you need lower).

App Icons: provide an iOS icon set (1024×1024 marketing icon in App Store Connect; all sizes via an asset catalog).

Launch screen: keep your existing storyboard or a simple branded screen.

3) iOS permissions & Info.plist

Add user-facing reasons for any capability your app uses (required for review):

NSMicrophoneUsageDescription: “We use the microphone to let you talk to your AI therapist.”

If you record audio in the background or play TTS while the app is backgrounded, add Capabilities → Background Modes → “Audio, AirPlay, and Picture in Picture.”

If you use push notifications: enable “Push Notifications” capability and add NSUserTrackingUsageDescription only if you actually track users across apps (most don’t).

App Transport Security: ensure the backend uses HTTPS (TLS 1.2+). Avoid ATS exceptions; if you must add one, justify it in the review notes.

4) Firebase on iOS (if you already use it on Android)

Add an iOS app in Firebase Console with your bundle id.

Download GoogleService-Info.plist and add it to ios/Runner/ (Xcode → Runner → drag file into project, “Add to targets” checked).

Run cd ios && pod install (CocoaPods).

If using FCM push: upload your APNs Auth Key (p8) to Firebase → Project Settings → Cloud Messaging; enable Push capability in Xcode.

If using Firebase Auth with third-party sign-ins (Google, etc.): Apple requires Sign in with Apple if you offer other third-party auth. Add the capability and flow, or restrict to email/password/phone only.

5) App Check / security (optional but recommended)

If you used Firebase App Check/Play Integrity on Android, configure DeviceCheck/App Attest on iOS (Firebase → App Check).

Keep a server-side allowlist during ramp to avoid lockouts.

6) Backend readiness (GCP)

Ensure CORS/headers are fine for iOS webviews (if any) and that endpoints are HTTPS only.

Validate SSL chain is complete; iOS is strict.

No additional work for Python/Cloud Run beyond capacity & logs.

If you use WebSockets for streaming audio, test on iOS device (cellular + Wi-Fi). Verify ALPN/HTTP/2 or fallbacks as needed.

7) Build & upload

Archive in Xcode: Product → Archive → Distribute App → App Store Connect → Upload.

Alternatively, export .ipa and use Apple’s Transporter app.

After processing finishes in App Store Connect, you’ll see your build under “TestFlight.”

8) TestFlight (strongly recommended)

Internal testing (up to 100 users with just their Apple IDs).

External testing requires Beta App Review (fast for most apps).

Verify: audio permissions prompt, streaming, background audio (if declared), push notifications, sign-in, and purchase flows (if any).

9) App Store submission

App Information: subtitle, keywords, support URL, marketing URL (optional).

Pricing & Availability (free/paid, regions).

In-App Purchases/Subscriptions (if any) configured and submitted for review. Use StoreKit testing receipts if relevant.

Screenshots: 6.7″ and 5.5″ required (you can add iPad sizes if you support iPad).

Age Rating questionnaire (mental-health content usually ends up 12+ or 17+ depending on claims).

“Made for Kids” should be off unless you truly target children.

App Review Notes:

Clarify that the app provides self-help/education, not medical advice.

Include crisis resources link and how users can access professional help.

Explain any ATS exceptions, background audio use, or sign-in flows.

10) Compliance gotchas for mental-health/voice apps

Include a clear disclaimer in onboarding and in Settings (e.g., “Maya is not a medical device, not for emergency use,” with a “Get Help Now” link to local crisis resources).

If you surface health-related claims, avoid diagnostic language.

If you collect voice data, say so in App Privacy and link to your policy describing retention and opt-out.

If you use third-party analytics, declare it precisely in Privacy Labels (e.g., coarse diagnostics vs tracking).

11) After approval

Turn on production feature flags as planned.

Monitor crashes (Firebase Crashlytics), performance, and backend logs for iOS traffic specifically.

Prepare the first hotfix build path (bump Build number in Xcode; re-archive and upload).

Minimal engineering changes you’ll likely make

Add the iOS Info.plist descriptions and (optionally) Background Audio capability.

Add GoogleService-Info.plist + CocoaPods for Firebase.

If you offer Google/Facebook login, add Sign in with Apple or remove third-party logins on iOS.

Verify audio streaming on iOS devices (WebSocket/TLS) and adjust any platform channels if you use native audio engines.

Quick sanity checks before you press Submit

First launch: permission prompt copy is friendly and clear.

Microphone works on both Wi-Fi and cellular; TTS plays with screen locked if you enabled background audio.

App icon and 1024px marketing icon look crisp on light and dark backgrounds.

No ATS exceptions needed (all requests over HTTPS).

App Privacy section matches what your code actually collects.

--------------------------------------------

Maya (Uplift) – iOS Launch Readiness Sheet
App Summary
Item	Detail
Framework	Flutter (cross-platform)
Backend	Python (FastAPI) on Google Cloud Run
Mobile Data Layer	Firebase Auth, Firestore/Realtime DB, App Check (Android & iOS)
Primary Features	AI voice session (TTS/ASR), mood logging, session tracking
Target Launch	App Store (iPhone only for v1)
1. Apple Developer Setup
Task	Owner	Status
Enroll in Apple Developer Program (Company)	Muneeba	☐
Create App Record in App Store Connect	Engineer	☐
Configure Bundle ID (e.g., com.mayaai.uplift)	Engineer	☐
Assign roles in App Store Connect (Admin, Developer)	Muneeba	☐
Upload app icons & marketing assets	Design	☐
2. Xcode Configuration (Runner target)
Setting	Value / Note
Bundle Identifier	com.mayaai.uplift
Display Name	Maya
Version / Build	1.0.0 / 1
Deployment Target	iOS 15.0+
Signing & Team	Automatic signing under Org account
App Category	Health & Fitness → Mental Wellbeing
Orientation	Portrait only
Background Modes	Audio & AirPlay (if voice streaming continues during lock)
3. Info.plist Declarations

Add the following keys and copy text exactly:

<key>NSMicrophoneUsageDescription</key>
<string>Maya uses the microphone so you can talk to your AI companion.</string>
<key>NSCameraUsageDescription</key>
<string>Used only if you choose to share a photo (not required).</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Optional – for profile photo customization.</string>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Used for connecting audio devices during sessions.</string>
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <false/>
</dict>


(Remove Camera/Photo/Bluetooth if not used.)

4. Firebase (iOS)
Step	Action
Add iOS app in Firebase Console (bundle id: com.mayaai.uplift)	☐
Download GoogleService-Info.plist → add to ios/Runner/	☐
Run pod install in /ios folder	☐
Verify analytics + crash reporting toggle	☐
App Check: enable DeviceCheck provider for iOS	☐
Push Notifications (if enabled): upload APNs .p8 key in Firebase → Cloud Messaging	☐
5. Feature Compliance (App Review Readiness)
Category	Requirement	Status
Privacy Policy URL	Publicly accessible HTTPS page	☐
Terms of Service URL	Publicly accessible HTTPS page	☐
App Privacy (Nutrition Label)	Declares microphone, diagnostics, crash data	☐
Health Disclaimer	“Maya is not a medical device…” visible on first use	☐
Crisis Resources	Link in Settings or Help (“Need immediate help?”)	☐
Analytics Disclosure	In Privacy Policy (Firebase Analytics only)	☐
Sign in with Apple	Required only if using Google/Facebook login	☐
6. Build & Archive Steps

In terminal:

flutter build ios --release
open ios/Runner.xcworkspace


In Xcode:

Product → Archive

Validate and upload to App Store Connect.

In App Store Connect:

Wait for build processing (≈15–30 min).

Verify version/build number appears under TestFlight.

7. TestFlight QA Checklist
Area	Test	Expected Result
Launch	App opens without splash freeze	✅
Permissions	Microphone prompt appears once, correct message	✅
Voice session	Audio streaming works (Wi-Fi + 4G)	✅
Mood logging	Mood persists, syncs across devices	✅
Offline mode	Mood logs saved locally, syncs later	✅
Push (if enabled)	Delivered in background	✅
Background audio	TTS playback continues with screen locked (if declared)	✅
Logout / Auth expiry	Graceful fallback, no crash	✅
Crash reporting	Verified in Firebase Crashlytics	✅
8. App Store Submission
Section	Notes
App Name	Maya: AI Therapist & Mood Journal
Subtitle	“Talk, reflect, and grow with your AI companion.”
Keywords	ai, therapy, mental health, journal, voice chat
Support URL	https://upliftapp.ai/support

Marketing URL	https://upliftapp.ai

Screenshots	6.7″ (iPhone 15 Pro Max) + 5.5″ (iPhone 8 Plus)
Age Rating	12+
Category	Health & Fitness
Content Rights	Affirm you own all code/audio
Export Compliance	Select “Yes, uses encryption,” then “No, not restricted under U.S. law.”
Review Notes	“Maya is a self-help app for mood tracking and guided AI conversation. It does not provide medical advice or emergency care.”
9. Post-Launch Monitoring
Task	Frequency	Tool
Crash & ANR rates	Daily first week	Firebase Crashlytics
Backend latency (Cloud Run)	15 min alerts	GCP Monitoring
App performance (TTS, streaming)	Manual QA	Internal tester
Feature flag toggles	Gradual rollout via Remote Config	Firebase RC
Reviews & feedback	Monitor App Store Connect dashboard	Continuous
10. Rollback Plan

If Apple flags anything or you detect critical iOS-only issues:

Disable iOS-specific feature flags (mood persistence, streaming) via Remote Config.

Remove build from sale (App Store Connect → Pricing & Availability → uncheck iOS).

Push hotfix build with bumped build number (e.g., 1.0.1).

✅ Summary: You’re ready for submission when

 Xcode build archived + uploaded successfully.

 Firebase fully configured (GoogleService-Info.plist, App Check).

 App privacy & disclaimer verified in onboarding.

 TestFlight internal testing passes full QA.

 Privacy URLs live.

 App Store Connect metadata complete.

-----------------------------------------

App Store Metadata (for App Store Connect)
App Name

Maya: AI Therapist & Mood Journal
(≤ 30 characters — approved format with brand + descriptor)

Subtitle

Talk, reflect, and grow with your AI companion.
(≤ 30 characters — emotionally inviting and keyword-rich)

Promotional Text

(Visible above the description; editable without new version)

Meet Maya — your personal AI companion for daily reflection, stress relief, and self-growth. Track moods, talk freely, and build healthier habits in a safe, private space.

Full Description

Maya is an AI-powered wellness companion that helps you understand and improve your emotional health.

🧠 Talk Freely — Have natural, judgment-free conversations with Maya anytime you need support.

💖 Track Your Mood — Log how you feel, add notes, and visualize your emotional trends over time.

🔄 Build Consistency — Earn streaks and gentle reminders that keep you connected to your wellbeing routine.

🔒 Private by Design — Your chats and mood logs are encrypted and never shared without consent.

🎧 Voice & Text Modes — Choose how you want to communicate — talk out loud or type quietly.

Maya isn’t a medical or crisis-response service, but it’s always here to listen and help you reflect, recharge, and grow.

Disclaimer: Maya provides self-help and educational support only. If you ever feel unsafe or in crisis, please contact your local emergency or crisis helpline.

Keywords

ai therapy, mental health, mood journal, self help, mindfulness, chatbot, wellness, anxiety, voice assistant, stress relief

Support URL

https://upliftapp.ai/support

Marketing URL

https://upliftapp.ai

Privacy Policy URL

https://upliftapp.ai/privacy

Terms of Service URL

https://upliftapp.ai/terms

App Category

Primary: Health & Fitness
Secondary: Lifestyle

Age Rating

12+ (for mild references to mental health and emotional themes)

Copyright

© 2025 Uplift AI Inc. All rights reserved.

App Review Notes

Maya is a self-help and wellness app that enables users to converse with an AI companion and log moods.

• No diagnostic or medical functionality.
• Microphone used only for live conversation sessions.
• All network traffic uses HTTPS; no ATS exceptions.
• If the reviewer wishes to test live audio sessions, please allow microphone access and start a session on the home screen.

Crisis resource link is provided under “Help & Support.”

Export Compliance

Uses standard HTTPS/TLS encryption.

Select “Yes, uses encryption” → “No, exempt from U.S. export regulations.”

App Previews & Screenshots (guidelines)
Device	Requirement	Suggestion
6.7″ (iPhone 15 Pro Max)	Required	Use the “Good Morning Hammad” home screen + session screen
5.5″ (iPhone 8 Plus)	Required	Mood-logging and conversation view
Optional	iPad 12.9″	Only if interface scales gracefully

Include brand-colored gradients (#FF4B70 → #FF7A9E), white bezel devices, and brief captions like “Track how you feel daily” or “Talk freely anytime.”

Localization Seeds

If you localize later, start with:

en-US primary

en-GB, en-CA, en-AU fallback copies

Metadata QA Checklist
Item	Limit	Ready?
App Name ≤ 30 chars	✅	
Subtitle ≤ 30 chars	✅	
Promo Text ≤ 170 chars	✅	
Description ≤ 4000 chars	✅	
Keywords comma-separated ≤ 100 chars	✅	
URLs HTTPS	✅	
Review Notes include permissions & disclaimer	✅	

------------------------------------------------

Maya (Uplift) – App Store Screenshot Pack
Goal

Communicate emotional warmth, privacy, and “AI companion” usefulness — in a clean, calming style (similar to Calm or Finch).
Use soft gradients, large typography, and 1 clear idea per frame.

1. Export Specs
Device	Resolution	Format	Count	Note
iPhone 6.7″ (15 Pro Max)	1290 × 2796 px	PNG, RGB, 72 DPI	5–6	Required
iPhone 5.5″ (8 Plus)	1242 × 2208 px	PNG, RGB, 72 DPI	5–6	Required
Optional iPad 12.9″	2048 × 2732 px	PNG	Optional	Only if layout scales well

Style baseline:

Background: light gradient (e.g., #FFF6F7 → #FFEFF2) or your accent pink gradient (#FF4B70 → #FF7A9E).

Rounded mock device frames (Apple default white or gray).

Caption font: SF Pro Display or Inter, bold headings (48–60pt on 6.7″).

Subtitle: 24–30pt, medium weight, 80% opacity.

Keep a consistent margin system (safe area: 120 px top/bottom).

2. Screenshot Order and Captions
Screenshot 1 — Hero / Welcome

Caption:
“Meet Maya — Your AI Companion for a Calmer Mind”
Subtext:
“Talk, reflect, and track how you feel — anytime, anywhere.”

Visual:
App home screen (“Good Morning, Hammad”) with the heart logo and gradient background.
Keep main CTA (“Start Session”) visible and centered.

Goal: first impression — premium and safe.

Screenshot 2 — Talk Freely

Caption:
“Talk Freely — No Judgment, Just Support.”
Subtext:
“Voice or text — Maya listens and responds naturally.”

Visual:
Conversation screen with speech bubbles and waveform animation mid-session.
Show both microphone and message icons to imply choice.

Goal: demonstrate AI conversation & voice clarity.

Screenshot 3 — Track Your Mood

Caption:
“Track Your Mood and Notice the Patterns.”
Subtext:
“Daily reflections help you understand your emotions.”

Visual:
Mood logging screen with emoji selection and notes area.
If possible, overlay a small mini-graph of mood trends.

Goal: show core mood tracking feature.

Screenshot 4 — Stay Consistent

Caption:
“Stay Consistent with Gentle Reminders.”
Subtext:
“Maya helps you build a simple daily check-in habit.”

Visual:
Show the “Consistency” card with streak days visible (“3-day streak” or “Tracking progress”).
Optional subtle notification banner “Time for your daily reflection?”

Goal: show that the app helps users build momentum without pressure.

Screenshot 5 — Privacy First

Caption:
“Private by Design. Your Data Stays Yours.”
Subtext:
“End-to-end encryption and secure cloud sync.”

Visual:
Lock icon with blurred background of chat screen.
Or a clean UI card saying “Encrypted • No data shared” overlayed on app screen.

Goal: signal trust, which is critical for review and user conversion.

Screenshot 6 (Optional) — Reflect & Grow

Caption:
“See Your Progress. Celebrate Your Wins.”
Subtext:
“Small check-ins add up to big changes.”

Visual:
Progress chart screen or positive streak summary.
Add subtle confetti or soft glow around graph.

Goal: emotional payoff — end on inspiration.

3. Design Notes

Tone: warm, supportive, trustworthy.

Palette: blush pink, soft coral, off-white, minimal black text.

Typography: bold + lowercase (approachable) or Title Case for calm authority.

Spacing: generous whitespace — let each message breathe.

Logo placement: upper-left or top-center; consistent across all shots.

CTA consistency: reuse pink accent on major UI buttons.

Animations: avoid busy visuals; still shots with motion blur are okay.

4. Export Checklist
Item	Target	Status
Device mockups use official Apple frames	✅	
Gradient background consistent across all	✅	
Captions localized for en-US only for launch	✅	
6.7″ and 5.5″ screenshots uploaded in correct order	✅	
All text legible against background	✅	
No overlapping status bar icons (battery, carrier)	✅	
PNGs ≤ 10 MB each	✅	
5. Optional “Premium Look” Tweaks

Add soft shadow behind each phone mockup for depth.

Apply subtle gradient overlays (white→transparent) to enhance caption readability.

Use micro-motion for App Preview video (fade-in logo → scroll → chat interaction).

Add tagline watermark bottom right on all images:
“upliftapp.ai • © 2025 Uplift AI Inc.”

-------------------------------------------------

Maya (Uplift) — App Preview Video Storyboard
Duration: 28 seconds
Aspect Ratio: 9 : 16 (vertical, 1080 × 1920 px)
Frame Rate: 30 fps
Format: MP4 (H.264 + AAC audio)
Audio: Soft ambient track + UI sounds (no narration; optional subtitle text)
Goal: Show calm, private, intelligent assistance that feels premium and trustworthy.
Scene-by-Scene Breakdown
Time (s)	Scene	Visuals	On-Screen Text / Caption	Sound / Motion
0 – 2 s	Opening Logo Reveal	Maya logo fades in over soft blush-pink gradient.	Maya
“Your AI companion for a calmer mind.”	Gentle chime; slow fade-in.
2 – 6 s	Home Screen Greeting	Home screen (“Good Morning, Hammad”) slides up; buttons shimmer slightly.	“Start each day with intention.”	Light piano tone; soft zoom.
6 – 11 s	Voice Session	Chat view shows voice waveform + reply bubbles; camera slowly pans across.	“Talk freely. No judgment.”	Mic pulse animation synced to voice waveform.
11 – 15 s	Mood Logging	Emoji row appears; user taps mood → note input field pops.	“Log your mood in seconds.”	Subtle click sound; fade to next.
15 – 19 s	Progress & Consistency	Animated streak counter and mini mood chart appear.	“See your progress and build healthy habits.”	Rising tone; confetti sparkle.
19 – 24 s	Privacy Focus	Lock icon overlay, blurred chat background.	“Private by design. Your data stays yours.”	Soft low note; fade glow around lock.
24 – 28 s	Closing CTA	Return to hero gradient + logo.
Button pulse: “Download Maya Today.”	“Find calm — anytime, anywhere.”	Music resolves; logo stays 1 s before fade-out.
Design & Production Notes

Font: Inter or SF Pro Display, SemiBold 48 pt for captions.

Color palette: #FF4B70 → #FF7A9E gradient + neutral off-white (#FAFAFA).

Motion style: ease-in-out curves; no sharp cuts.

Captions: White text with soft shadow or semi-transparent pink bar (70 % opacity).

Soundtrack: royalty-free calm piano/ambient loop (~60 BPM, C major).

Length limit: Apple recommends 15–30 s max; target 28 s including logo fade.

No requirements: Avoid device frames, “App Store,” “iPhone,” or testimonial quotes.

Deliverables for Upload
File	Spec	Notes
maya_app_preview_6_7inch.mp4	1080 × 1920 px @ 30 fps ≤ 500 MB	Required
maya_app_preview_5_5inch.mp4	886 × 1920 px @ 30 fps	Optional but recommended
music_track.wav	separate clean stem	For future reuse in marketing
✅ Quick QA Before Upload

 Captions match on-screen actions exactly.

 Background audio licensed and royalty-free.

 All text ≥ 24 pt for legibility on 5.5″ devices.

 Total ≤ 30 seconds.

 Ends with logo + brand URL (optional).

 ---------------------------------------

 