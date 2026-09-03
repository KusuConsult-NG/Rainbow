# Deploying Operation Rainbow to production

Three deliverables ship independently: the **database** (Supabase), the **HQ
console** (Next.js) and the **mobile app** (Flutter). Do them in that order —
the console and the app both expect the migrations to be in place.

Nothing in this document needs a credential pasted into a chat, a ticket or a
log. Where a secret is involved, it is set in a hosting provider's environment
UI or a local `.env.local` that is never committed.

> **`scripts/verify_rls.js` INSERTs probe rows. Never run it against
> production** — a throwaway staging project only.

---

## 0. Before anything: rotate what leaked

The git-history purge (H-6) removed the leaked material from every commit, but
**a purge is not a rotation**. Anyone who cloned the repository before it still
holds working credentials. Rotate these first, because the deployment steps
below will ask you to paste the new values into the hosting environment anyway:

| Credential | Where it is rotated | Where the new value goes |
|---|---|---|
| Supabase secret (service role) key | Supabase → Project Settings → API | `SUPABASE_SERVICE_ROLE_KEY` in the console's host env |
| Firebase Android API key | Google Cloud console → Credentials | nowhere — the app no longer uses Firebase |
| Firebase iOS API key | Google Cloud console → Credentials | nowhere — same |
| Cloudinary API secret | Cloudinary → Settings → Security | server only; the app uses an unsigned preset |
| Termii API key | Termii dashboard | `TERMII_API_KEY` in the console's host env |
| `HQ-001` / `HQ-002` / `COMMANDER-TEST` passwords | Supabase → Authentication → Users | nowhere; they are login credentials |

Also settle **C-6** while you are in the Google console: `firebase functions:list
--project rainbow-97f1e`. If `smsWebhook` or `seedMockData` is listed, an
unauthenticated stranger can inject `DURESS`-flagged emergencies today. Delete
the deployment — nothing in either client calls any of those 25 functions. Do
**not** `curl seedMockData` to find out; the probe itself writes ten fabricated
emergencies. The full instructions are in `E2E_AUDIT_REPORT.md`.

---

## 1. Database

Six migrations, in filename order. `docs/APPLYING_THE_MIGRATIONS.md` is the
step-by-step runbook, including the mandatory read-only dry run; do not apply
the RLS migration without it.

| Order | File | What it does |
|---|---|---|
| 1 | `20260812000000_agency_tables.sql` | Creates the four `agency_*` tables and `profiles.agency`. **On production these already exist and this is a no-op**; it exists so a staging or DR project is not missing the agency portal's backend. |
| 2 | `20260813000000_rls_least_privilege.sql` | Closes C-3/C-4/H-7. Needs the dry run first. |
| 3 | `20260902000000_per_user_emergency_pins.sql` | Per-user, server-verified duress PINs. |
| 4 | `20260903000000_realtime_publication.sql` | Adds the three tables the console subscribes to that were never published. |
| 5 | `20260903000001_incident_media_storage.sql` | Creates and secures the `incident-media` bucket. |
| 6 | `20260903000002_system_alerts_broadcast.sql` | Makes mass broadcast work. Until it runs, every broadcast fails on a NOT NULL `title` and six non-existent columns. |

All six are idempotent and every one of them is proven on a real PostgreSQL by
the `rls-migration` CI job before it reaches you.

### After applying, verify (read-only)

```sql
-- Expect 8 rows: the tables both apps subscribe to for realtime.
select tablename from pg_publication_tables
 where pubname = 'supabase_realtime' and schemaname = 'public' order by 1;

-- Expect 1 row, public = true, file_size_limit = 52428800.
select id, public, file_size_limit, allowed_mime_types
  from storage.buckets where id = 'incident-media';

-- Expect the two incident_media_* rows: upload (INSERT) and staff list
-- (SELECT). No UPDATE and no DELETE policy — evidence is append-only.
select policyname, cmd, roles from pg_policies
 where schemaname = 'storage' and tablename = 'objects' order by policyname;
```

If that last query returns other policies on `storage.objects` — ones created by
hand in the dashboard for this bucket — they are additional PERMISSIVE grants
and OR together with these. Drop them, or the append-only guarantee is not one.

---

## 2. HQ console

### There is no deploy target configured in this repository

`next.config.ts` says Firebase App Hosting, and `deploy.sh` runs `firebase
deploy --only hosting` — but **there is no `firebase.json`, no
`apphosting.yaml`, and no `vercel.json`**. `deploy.sh` therefore stops with a
hard failure at the deploy step rather than running a command that looks like it
worked. That is deliberate: pick a host, then add its config file.

Whichever you choose, it must run **Node.js, not static export**. `output:
'export'` was removed because the auth guard is Next.js middleware, and a static
export silently drops middleware — the console would serve every page to
anonymous visitors with no error anywhere.

* **Firebase App Hosting** — add `apphosting.yaml` at the repo root, set the
  environment variables in it (secrets via Secret Manager, never in the file),
  and change `deploy.sh` to `firebase deploy --only apphosting`.
* **Vercel** — connect the repo with root directory `hq-dashboard-next`; the env
  vars go in the project settings. `deploy.sh` is then unnecessary.
* **A container** — `npm ci && npm run build && npm start`, port from `$PORT`.

### Environment

Every key is documented in `hq-dashboard-next/.env.example`. The ones that must
be set for the console to work at all:

```
NEXT_PUBLIC_SUPABASE_URL          public, baked into the bundle at build time
NEXT_PUBLIC_SUPABASE_ANON_KEY     public, same
SUPABASE_SERVICE_ROLE_KEY         SECRET, server only — never NEXT_PUBLIC_
```

`NEXT_PUBLIC_*` values are inlined **at build time**, so a missing one is not a
runtime warning: the app crashes on first render and serves
`<html id="__next_error__">`. Set them before the build, not after.

**`NEXT_PUBLIC_DEV_DEMO_PIN` must be unset in production.** The quick-fill login
presets are already compiled out (`NODE_ENV !== 'production'`), and CI asserts
the demo credentials are absent from the production bundle, but leaving a real
PIN in the environment of a non-production build re-publishes it.

`deploy.sh` re-scans the built client bundle for server secrets before it will
deploy, the same scan CI runs. Keep that step in whatever replaces it.

---

## 3. Mobile app

```bash
flutter build appbundle --release      # Play Store
flutter build ipa --release            # App Store
```

* **`.env` must exist at the repo root.** `pubspec.yaml` declares it as a
  Flutter *asset*, so the build fails outright without it. Copy `.env.example`
  and fill in `HQ_API_BASE_URL` and the Cloudinary values. Everything in that
  file ships inside the APK and extracts with `unzip` — it holds no secrets any
  more, and nothing secret may be added to it.
* **Signing.** `android/app/build.gradle.kts` reads `key.properties` from the
  repo root (gitignored, along with `*.jks` and `*.keystore`). If that file is
  missing the release `signingConfig` is left with null fields and the build
  produces an **unsigned** artifact that the Play Store rejects — it does not
  fall back to the debug key and it does not warn. Create it:

  ```properties
  storeFile=/absolute/path/to/upload-keystore.jks
  storePassword=…
  keyAlias=upload
  keyPassword=…
  ```

* **No Firebase config is needed.** The `com.google.gms.google-services` plugin
  was applied with no Firebase dependency in `pubspec.yaml`; it fails the build
  when `android/app/google-services.json` is missing, and that file is
  gitignored, so release builds could not succeed on a clean checkout. It has
  been removed from both Gradle files and the `GoogleService-Info.plist`
  references are gone from the Xcode project. A CI gate keeps them out.
* **Version.** `pubspec.yaml` is at `1.0.7+28`. Bump both parts before each
  store upload; the build number must increase or the store rejects the upload.
* Push notifications go through OneSignal, configured in the console's
  environment, not in the app.

---

## 4. After the first production deploy

* Sign in as a command user and confirm the board loads and the map draws — an
  RLS mistake shows up here first, as an empty board rather than an error.
* Confirm an alert raised on a phone appears on the board **without a reload**;
  that is the realtime publication working.
* Raise a test SOS with a photo and confirm the image renders in the console;
  that is the storage bucket and its policies working.
* Send a test broadcast scoped to one LGA and confirm it reaches a device in
  that LGA and **not** one outside it. Audience and geography were both silently
  ignored before; a success message from the console is not evidence.
* Set an emergency PIN under Settings → Emergency PIN on a device, then cancel a
  test SOS with it. Until a user sets one, cancellation reports `UNSET` and
  refuses — intended fail-closed behaviour, but worth seeing once.
* Review Supabase logs for anonymous reads of `profiles` and `telemetry` from
  before the RLS migration.
