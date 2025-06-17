# Habit Logger – Requirements Document

## 1. Overview
Habit Logger is a cross-platform Flutter mobile application that helps users log their daily activities, track habits, and analyse how they spend their time.  All user data is stored securely in Firebase (Authentication, Cloud Firestore).

---

## 2. Functional Requirements

1. **Authentication**
   - Support Google Sign-In (primary) and email/password (future).
   - Persist authentication state across app launches.
   - Sign-out option in Settings.

2. **Timeline Logging**
   - Display one-hour blocks for the selected day (00 → 23).
   - Contains a setting page that allows user to: pick sleep and wake up time and select categories they want to log. Basic categories should be pre created like (Sleep, Work, Exercise, Study, Social, Hobby, Other)
   - Allow the user to pick a _category_ from defined options (Sleep, Work, Exercise, Study, Social, Hobby, Other) for each block.
   - Provide a multiline _notes_ field for each block, editable inline.
   - Autosave changes to Firestore instantly (no separate Save button per block).
   - Autofill Sleep blocks based on user Sleep/Wake settings.
   - Horizontal **Calendar Strip** (–7 … +7 days) above the timeline:
     - Today highlighted with secondary colour.
     - Currently selected date highlighted with primary colour.
     - On first load the strip scrolls so that _today_ is scrolled to wake up time.

3. **Habit Tracker**
   - Allow user to create habits and for each habit choose if it will a done or not, or a counter for example some habit need to store a counter.
   - Show the user's habits in a list with a daily checkbox (today) or counter.
   - Add / edit / delete habits.
   - Habits should also have calendar at the top like timeline.

4. **Settings**
   - Sleep & Wake time pickers (TimeOfDay widgets).
   - Store settings under `user_settings/{uid}` in Firestore (keys: `sleepTime`, `wakeTime`, `customCategories`).
   - create a list of categries with pre filled categories.
   - When dialog opens current values are pre-loaded.

5. **Navigation**
   - Login ⇒ Home.
   - Bottom-navigation (or Drawer) in Home: Timeline, Habits, Settings.

6. **Data Model / Firestore**
   - **timeline_entries**
     ```
     {
       id: Auto,           // Firestore doc id
       userId: string,     // owner
       date: Timestamp,    // midnight of the day
       startTime: Timestamp,
       endTime: Timestamp,
       category: string,
       notes: string
     }
     ```
   - **habits**
     ```
     {
       id: Auto,
       userId: string,
       name: string,
       createdAt: Timestamp,
       completedDates: List<Timestamp>
     }
     ```
   - **user_settings**
     ```
     {
       sleepTime: "HH:mm",
       wakeTime:  "HH:mm",
       customCategories: List<string>
     }
     ```

---

## 3. Non-Functional Requirements

| Area               | Requirement                                                |
|--------------------|------------------------------------------------------------|
| Platform           | Flutter 3, Dart ≥ 3.8                                      |
| Minimum Android    | SDK 23                                                     |
| Minimum iOS        | iOS 13 (future)                                           |
| Packages           | firebase_core, firebase_auth, cloud_firestore, google_sign_in, intl |
| State Management   | setState (initial), consider Riverpod/Bloc later           |
| Testing            | Unit + widget tests for models & critical UI (future)      |
| Accessibility      | Colour contrast, Labelled controls                         |
| Analytics          | Firebase Analytics (optional)                              |

---

## 4. Screen-by-Screen Details

### 4.1 Login Screen
- App logo.
- "Continue with Google" button.
- Progress indicator while signing in.
- Navigate to Home on success.

### 4.2 Home Screen
- App Bar with title & sign-out action.
- Bottom Navigation Bar items:
  - Timeline
  - Habits
  - Settings

### 4.3 Timeline Screen
1. **Calendar Strip** (top)
   - 14 days, horizontally scrollable.
2. **Timeline List** (body)
   - 24 cards (hour blocks).
   - Each card shows:
     - Time label (HH:00)
     - Category dropdown
     - Notes TextField (max 2 lines)
   - Border colour changes when a category is selected.
   - When screen opens it auto-scrolls so that Wake Time card is visible.
3. **Settings Icon** in App Bar (quick access to sleep settings).

### 4.4 Habits Screen
- FAB to add habit (dialog with name field).
- ListTile per habit with today's checkbox.
- Swipe to delete (future).

### 4.5 Settings Dialog / Screen
- Sleep Time row → TimePicker.
- Wake Time row  → TimePicker.
- Save & Cancel buttons.

---

## 5. Future Enhancements (Backlog)
1. Dark mode specific colour tweaks.
2. Offline support & local caching.
3. Advanced analytics dashboard (charts).
4. Push notifications for habit reminders.
5. Internationalisation using `intl`.
6. Custom categories management UI. 