# DentPass

A mobile app for dentists in Egypt to post and book four kinds of slots:

- **Watch a case**: seats to observe an expert's case
- **Course**: hands-on teaching for a group
- **Chair for rent**: a unit or chair by the day or hour
- **Cover needed**: a dentist or assistant to cover a shift

Arabic first (right to left), with an English switch. Every member is checked against their syndicate card and national ID before they can post or book.

Built with **Flutter** (one codebase for Android and iPhone) and **Supabase** (database, sign-in, file storage).

---

## What's included

| Part | Where |
|---|---|
| Database, security rules, booking logic, storage buckets | `supabase/migrations/0001_init.sql` |
| App screens | `lib/screens/` |
| Arabic and English text | `lib/l10n/app_ar.arb`, `lib/l10n/app_en.arb` |
| Colours and type | `lib/theme.dart` |
| Areas (Cairo and Giza for the pilot) | `lib/data/areas.dart` |
| All server calls | `lib/data/repo.dart` |

### Screens

1. **Sign in / create account** (email and password)
2. **Verification**: name, mobile, dentist or assistant, syndicate number, area, photos of the syndicate card and national ID
3. **Waiting for approval**
4. **Explore**: all open slots, filtered by type and area, shown as tickets
5. **Slot details**: when, where, price, places left. The exact address and the host's phone appear only after the host accepts.
6. **Review and confirm**: price, DentPass fee and total, an optional message, then "Send request"
7. **Post a slot**: type, title, details, area, address, date, times, seats or people needed, price, optional photo
8. **Bookings**: "My bookings" with their status and cancel, and "My posts" with how many requests are waiting
9. **Manage requests** (host): accept or decline, close the slot, call or WhatsApp people you accepted
10. **Notifications**: new requests, accepted, declined, cancelled, account approved
11. **Profile**: language switch, sign out, and for admins, **Review new members** to approve or reject documents

### How a booking works

1. A member sends a request. For seats and chairs, a place is held while the request waits.
2. The host accepts or declines. Accepting shares the address and phone numbers both ways.
3. Payment happens outside the app for now: the member pays the host by InstaPay after acceptance.
4. Either side can see the status at any time, and the member can cancel.

Cover offers are not limited: several people can offer, and the host accepts as many as they need.

The database enforces all of this, not just the app: nobody can approve themselves, book their own slot, overbook a slot, or read someone else's documents. These rules were tested against Postgres 16.

---

## Setup

### 1. Supabase (about 15 minutes)

1. Create a free project at [supabase.com](https://supabase.com).
2. Open **SQL Editor**, paste all of `supabase/migrations/0001_init.sql`, and run it.
3. Go to **Authentication → Providers → Email**: keep email sign-in on, turn on **Confirm email**, and set the minimum password length to 8.
4. Go to **Project Settings → API** and copy the **Project URL** and the **anon public** key. Never put the `service_role` key in the app.

### 2. Make yourself the first admin

Create your account in the app first, then run this in the SQL Editor with your email:

```sql
update public.profiles
set is_admin = true, status = 'approved', full_name = 'Your name'
where id = (select id from auth.users where email = 'you@example.com');
```

### 3. Flutter

You need Flutter 3.35 or newer.

```bash
cd dentpass
# Creates the android/ and ios/ folders. Your lib/ files are kept as they are.
flutter create --org com.dentpass --project-name dentpass --platforms android,ios .
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR-ANON-KEY
```

`flutter pub get` also generates the translation code from the `.arb` files.

### 4. Platform settings (after `flutter create`)

**Android:** in `android/app/src/main/AndroidManifest.xml`, add this inside `<manifest>` so the Call and WhatsApp buttons work:

```xml
<queries>
  <intent><action android:name="android.intent.action.DIAL" /><data android:scheme="tel" /></intent>
  <intent><action android:name="android.intent.action.VIEW" /><data android:scheme="https" /></intent>
</queries>
```

**iPhone:** in `ios/Runner/Info.plist`, add:

```xml
<key>NSCameraUsageDescription</key>
<string>DentPass uses the camera to photograph your syndicate card, ID and clinic.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>DentPass uses your photos to add your syndicate card, ID and clinic pictures.</string>
<key>LSApplicationQueriesSchemes</key>
<array><string>tel</string><string>https</string><string>whatsapp</string></array>
```

### 5. Release builds

```bash
flutter build appbundle --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...   # Google Play
flutter build ipa       --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...   # App Store
```

---

## Web version (works on iPhone and Android, no app store)

Every push to `main` builds the app for the web and publishes it with GitHub Pages
(`.github/workflows/web.yml`). It opens at `https://<github-username>.github.io/dentpass/`.
On an iPhone, open it in Safari, tap **Share**, then **Add to Home Screen**.

One-time setup on GitHub:

1. **Settings → Pages → Source:** choose **GitHub Actions**.
2. **Settings → Secrets and variables → Actions → Variables:** add `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
3. In Supabase, **Authentication → URL Configuration:** set **Site URL** to the Pages link and add it under **Redirect URLs**, so confirmation emails bring people back to the app.

---

## Changing things

- **DentPass fee:** in the SQL Editor run `update public.app_settings set fee_percent = 10;` with your percentage. The app shows the new fee straight away. People offering cover pay no fee.
- **Areas:** edit `lib/data/areas.dart`. Each area has an English and an Arabic name.
- **Text:** edit `lib/l10n/app_ar.arb` and `lib/l10n/app_en.arb`. Keep the same keys in both.
- **Colours:** `lib/theme.dart`. Each slot type has its own colour pair in `lib/ui/kinds.dart`.

---

## Not built yet (version 2)

- In-app payment (Paymob or Fawry) with deposits and a cancellation policy
- Push notifications (Firebase Cloud Messaging). Version 1 shows notifications in the app only.
- Ratings after each slot
- Map and distance
- Editing a slot after posting (hosts can close it and post again)
- Search by keyword
- Chat inside the app

---

## Before launch

- **Test on real phones.** This code was written without access to a Flutter build tool, so run `flutter analyze` first and fix anything it reports. Expect only small fixes.
- **Privacy policy:** both app stores require one, and you are storing ID and syndicate card photos. Have a lawyer check it against Egypt's Personal Data Protection Law (Law 151 of 2020).
- **Terms of use:** set out who is responsible during a slot: treatment, materials, patient consent for observers, and payment between members.
- **Ownership:** keep the Supabase project, app store accounts and code in the company's name.
