# Bond Touch iOS app — recovered structure

Facts recovered from the official iOS app binary (`BONDTouch` 7.4.5, `com.impossible.bondtouch`).
The binary is FairPlay-encrypted, so the executable code is not readable, but the Swift type
metadata, source paths and resource files are, which gives the module layout, the screen
inventory and the authentication flow. The UI is SwiftUI (only a Launch Screen storyboard
exists), so there are no editable layout files; pixel layout comes from the screenshots.

## Authentication (Firebase Email Link)

- iOS Firebase config (`GoogleService-Info.plist`): project `bond-touch`, API key
  `AIzaSyBKWjCliQP5HvvM6QtTQfFaGTvD27847_c`, `GOOGLE_APP_ID 1:625752440215:ios:842cd2b4e290f0e5`,
  `DATABASE_URL https://bond-touch.firebaseio.com`, `STORAGE_BUCKET bond-touch.appspot.com`.
- The app signs in with Firebase **Email Link**: `sendSignInLink(to:actionCodeSettings:)` then
  `signInWithEmailLink(email:link:)` (classes `EmailLinkSignInRequest/Response`,
  `EmailLinkAllSetViewController`, `ActionCodeSettings`). Firebase keys are authorised with the
  `X-Ios-Bundle-Identifier` header.
- The Bond REST API (`api.bond-touch.com/bond/api/v3/...`) is then called with the Firebase ID
  token as a bearer. Endpoints are in `docs/DATA_MODEL.md`.

## Source tree (`BondSwiftUI/`)

```
App/ (Navigation)
Core/Extensions
Data/{Migration, Models, Network, Storage}
DesignSystem/
  Components/{Chat, Gallery, SettingsRows, Snackbar, Subscription, Tutorials}
  Foundation
  Heart/{SettingsRows}
Features/
  Campaign/Views
  Chat/{Models, Views}
  Dashboard/{Views, DashboardOverlays/Components}
  Heart/{Models, Views/{Connection, Dashboard, Library, Recording, Settings, Tutorials}}
  Meanings/Views
  Onboarding/
    AgeVerification
    Auth
    Connection/{Bluetooth, Complete, Components, DFU, DeviceList, Models, Setup, Subscription, Tutorials}
    Profile
  Partner/Views
  Presence/Views
  Settings/{Views, Subviews}
  Tutorials/{Models, Views/{Interactive, Lessons}}
Services/{Analytics, Auth, Bluetooth, Campaign, ...}
```

## Screen inventory (selected, of ~516 SwiftUI views)

- Dashboard: `DashboardView`, `DashboardContentView`, `DashboardPagerView`, `DashboardEmptyView`,
  `DashboardRequestedView`, `DashboardMessageEditorView`, `DndSettingsOverlayView`.
- Meanings (Touch Language): `CreateMeaningFlowView`, `AddMeaningLessonView`, `EditMeaningColorView`,
  `EditMeaningTextView`, `FirstMeaningColorPickerView`, `BondLiteMeaningColorPickerView`.
- Partner: `AddPartnerView`, `AddPartnerEmailView`, `AddPartnerColorPickerView`,
  `AddPartnerIconPickerView`, `AddPartnerLessonView`, `EditPartnerColorView`, `EditPartnerIconView`.
- Chat: `ChatConversationView`, `ChatInputBar`, `ChatMessageCell`, `ChatPagerView`,
  `ChatPartnerListCell`, `ChatTopBarView`, `ChatImageEditorView`, `ChatCipherSetupView`,
  `ChatSwipeActionView`.
- Settings: `DeviceSettingsView`, `DNDSettingsView`, `BraceletNotificationsSettingsView`, plus
  many `*SettingsCell` / `*SettingsRow` components.
- Heart: `HeartConnectionFlowView`, `HeartAddHeartbeatView`, `HeartColorPickerView`,
  `HeartCameraPreviewView`, `HeartCustomizeFlowView`, and the Heart tutorials.
- Presence: `AboutPresencePlusView` and the Presence map views.

The full lists are extracted to the reverse-engineering scratch; this file records the facts used
to mirror the structure.
