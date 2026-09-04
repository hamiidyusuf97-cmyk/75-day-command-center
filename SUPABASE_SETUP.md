# Shared Accountability Setup

The dashboard currently has browser-local data. The shared participant experience requires Supabase so authentication, ownership, realtime updates, and Row Level Security are enforced outside the browser.

## 1. Create the backend

1. Create a Supabase project.
2. Open the SQL editor and run `supabase-schema.sql`.
3. Enable email/password authentication, or enable the provider you want to use.
4. Create a Storage bucket named `evidence-photos` and configure authenticated users to upload only under their own user ID prefix. Keep the bucket private if photos should require signed URLs.
5. Copy the project URL and anon public key.

## 2. Configure the dashboard

Set these values in the dashboard's Supabase configuration block:

```js
const SUPABASE_URL = "https://YOUR_PROJECT.supabase.co";
const SUPABASE_ANON_KEY = "YOUR_PUBLIC_ANON_KEY";
```

Only the anon public key belongs in browser code. Never place the service-role key in the HTML.

## 3. Ownership model

- Authenticated users can read shared profiles, logs, progress, leaderboards, and shared evidence.
- Users can insert, edit, and delete only rows with their own `user_id`.
- Admins are additive: `profiles.is_admin = true` grants administrative writes without reducing normal participant visibility.
- Leaderboard values are calculated from `daily_logs`; clients cannot write a score or streak field.
- Missed workout counts are calculated from log dates and task evidence in the shared view.

## 4. Realtime

Subscribe to `profiles`, `daily_logs`, and `evidence_photos` through Supabase Realtime. On a change, refresh the shared participant view and leaderboard. Keep private notes or non-shared evidence out of the public projection if the product later introduces private fields.

## 5. Existing local data

The current browser-local data is not automatically uploaded because doing so without an authenticated user mapping could assign someone else's data incorrectly. After authentication is configured, add an explicit one-time import flow that lets each user review and confirm which local records belong to them before inserting them into `daily_logs` and `evidence_photos`.
