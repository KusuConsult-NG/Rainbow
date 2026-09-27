# Setting up a staging project

Everything in this repository is proven against a throwaway PostgreSQL: the
migrations, the policies, the behaviour of each role. That harness cannot prove
one thing, and it is the thing that has bitten this system hardest — **what a
live Supabase actually does.**

A local replica has no PostgREST, no Auth service, no Storage service, and above
all none of the policies somebody created by hand in the dashboard. Production
had 44 policies where a replica rebuilt from this repo had 21. Twenty-three
existed only in a place no test could see.

A staging project closes that gap. It costs one free Supabase project and about
ten minutes.

---

## 1. Create the project

Supabase dashboard → **New project**. Free tier is enough.

Name it so nobody can mistake it for production — `rainbow-staging`, not
`rainbow-2`. Every destructive tool in this repository is guarded, but the
guards are a second line; the first is that the tab you are looking at says what
it is.

## 2. Build the schema

Supabase dashboard → **SQL Editor**, paste the whole of:

```
scripts/bootstrap_staging.sql
```

All fourteen migrations, in order, ending in a sixteen-row PASS/FAIL table.
Every row should say PASS.

**This file is for an empty project only.** It starts with the original schema,
whose policies are `USING (true)` — wide open to `anon` — and a later migration
removes them. On an empty project that is a safe path to the right end state; on
a database with data in it, that path runs briefly through an open door. The
file is one transaction and refuses to start if it finds rows in `alerts`, so
the mistake rolls back rather than half-applying, but the guard is not a reason
to skip reading this paragraph.

For production, the file you want is `scripts/apply_all_migrations.sql`, which
omits the four historical migrations because production already has them.

> CI runs `scripts/verify_bootstrap.sh` on every push: it builds an empty
> database, pastes this file into it, checks the guard refuses a non-empty one,
> and proves the result is byte-identical in policy terms to replaying the
> migrations one at a time. The file has been executed, not just assembled.

## 3. Turn on what the apps need

Two things the SQL cannot do for you, both in the dashboard:

* **Authentication → Providers → Email**: enable it, and turn **off** "Confirm
  email". The seeder creates accounts with `email_confirm: true`, but a human
  adding a test account later will otherwise be stuck waiting for mail sent to a
  domain that does not exist.
* **Storage**: the `incident-media` bucket is created by the migration. Nothing
  to do — but check it is listed, because a missing bucket makes every media
  upload fail at the point where somebody is trying to report an emergency.

## 4. Seed it

A correct empty schema proves anon is locked out. It does not show whether the
console works, because every role in this system sees a different slice.

```bash
SUPABASE_URL=https://<ref>.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=<staging service key> \
RAINBOW_ENV=staging \
node scripts/seed_staging.js
```

Six accounts — citizen, responder, LGA command, HQ command, police liaison, army
liaison — and five incidents chosen to make previously-real defects visible:

| what to look at | why |
|---|---|
| the SOS with no coordinates | must read UNLOCATED, not a pin in central Jos (C-5) |
| the ungraded incident | must read UNKNOWN and stay out of the CRITICAL filter |
| the JOS NORTH broadcast | must **not** reach the Mangu-based army liaison |
| the escalated incident | must appear in the ARMY portal and no other |

`RAINBOW_ENV=staging` is required. The seeder creates accounts with a known
password and writes fabricated emergencies; on a live project that is a back
door and a false dispatch. The variable exists to make running it a decision
rather than a command-history accident.

## 5. Point the apps at it

Console — `hq-dashboard-next/.env.local`:

```
NEXT_PUBLIC_SUPABASE_URL=https://<ref>.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<staging anon key>
SUPABASE_SERVICE_ROLE_KEY=<staging service key>
```

Mobile — the app reads `HQ_API_BASE_URL` from the root `.env`; point it at
wherever you run the console.

## 6. Now the thing a replica could never tell you

```bash
NEXT_PUBLIC_SUPABASE_URL=https://<ref>.supabase.co \
NEXT_PUBLIC_SUPABASE_ANON_KEY=<staging anon key> \
node scripts/verify_rls.js
```

This is the whole reason for the exercise. It talks to a **real** PostgREST with
a **real** anon key and tries to read and write every sensitive table. A local
harness can prove the policies are right; only this can prove the deployed
system enforces them.

> **Never run it against production.** It INSERTs probe rows. That is why it is
> in this document and not in the production runbook.

---

## Keeping it honest

A staging project drifts the moment somebody fixes something in its dashboard
instead of in a migration — which is exactly how production ended up with 23
policies that existed nowhere else.

Two habits prevent it:

* **Fix it in a migration, then re-bootstrap.** Deleting and recreating the
  project takes minutes, and a staging project you are willing to throw away is
  the only kind that stays trustworthy.
* **Run the inventory before you trust it.** `scripts/rls_inventory.sql` lists
  every policy and flags the ones this repository does not create. On a freshly
  bootstrapped project that list should be empty; if it is not, something was
  added by hand.

## What this still does not cover

Being honest about the edges, since the point of staging is to stop guessing:

* **Deployment.** The App Hosting config has never been executed. Staging
  proves the database; the first real deploy is still the first real deploy.
* **The mobile release build.** No Android or iOS build has run here — the
  Gradle and Xcode changes are gated statically only.
* **Load.** A free-tier project with six users says nothing about behaviour
  under a real incident.
