# Habit Logger – Task Checklist

| # | Task | Status |
|---|------|--------|
| **Project Setup** |||
| 1 | Initialise Flutter project | ☑️ Done |
| 2 | Set up Git repository | ☑️ Done |
| 3 | Add `docs/` folder with requirements | ☑️ Done |
| **Firebase Integration** |||
| 4 | Create Firebase project | ☑️ Done |
| 5 | Add Android app SHA-256, download `google-services.json` | ☑️ Done |
| 6 | Add iOS app & `GoogleService-Info.plist` | ⬜ TODO |
| 7 | Configure `build.gradle` / Kotlin versions | ☑️ Done |
| 8 | Enable Email/Google auth providers | ☑️ Done |
| **Packages & Build** |||
| 9 | Add `firebase_core`, `firebase_auth`, `cloud_firestore`, `google_sign_in` | ☑️ Done |
| 10 | Add `intl` for date formatting | ☑️ Done |
| 11 | Migrate to Dart 3 (>=3.8) | ☑️ Done |
| **Authentication** |||
| 12 | Google Sign-In flow | ☑️ Done |
| 13 | Persist auth state across launches | ☑️ Done |
| 14 | Sign-out action | ☑️ Done |
| **Models** |||
| 15 | `TimelineEntry` model | ☑️ Done |
| 16 | `Habit` model | ☑️ Done |
| 17 | `UserSettings` model | ☑️ Done |
| **Widgets** |||
| 18 | `CalendarStrip` widget | ☑️ Done |
| 19 | Auto-scroll to today on load | ☑️ Done |
| **Screens** |||
| 20 | Login Screen | ☑️ Done |
| 21 | Home Screen w/ navigation | ☑️ Done |
| 22 | Timeline Screen with 1-hour blocks | ☑️ Done |
| 23 | Habit Tracker Screen | ☑️ Done |
| 24 | Sleep Settings Dialog | ☑️ Done |
| **Timeline Features** |||
| 25 | Inline activity dropdown per block | ☑️ Done |
| 26 | Inline notes TextField per block | ☑️ Done |
| 27 | Autosave to Firestore on change | ☑️ Done |
| 28 | Scroll timeline to Wake Time | ☑️ Done |
| 29 | Highlight selected & today in CalendarStrip | ☑️ Done |
| 30 | Autofill Sleep blocks based on settings | ☑️ Done |
| 31 | Custom Activities (user defined) | ☑️ Done |
| 32 | Settings dialog improvements | ☑️ Done |
| **Habits Features** |||
| 33 | Add habit dialog | ☑️ Done |
| 34 | Mark habit complete for today | ☑️ Done |
| 35 | Habit counter type support | ⬜ TODO |
| 36 | Calendar strip in Habits screen | ⬜ TODO |
| **Settings** |||
| 37 | Persist Sleep & Wake time in Firestore | ☑️ Done |
| 38 | Load settings in dialog | ☑️ Done |
| 39 | activity management in settings | ☑️ Done |
| **Testing & CI** |||
| 40 | Unit tests for models | ⬜ TODO |
| 41 | Widget tests for Timeline & CalendarStrip | ⬜ TODO |
| 42 | Set up GitHub Actions CI | ⬜ TODO |
| **UX / Polish** |||
| 43 | Dark mode theming | ⬜ TODO |
| 44 | Error handling & snackbars | ⬜ TODO |
| 45 | Offline persistence settings | ⬜ TODO |

---

Legend: ☑️ **Done** · ⬜ **TODO** 