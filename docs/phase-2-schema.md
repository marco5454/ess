# Phase 2 — Schema Design

Status: **DRAFT** — for review before writing SQL migrations.

This document defines the initial Supabase (Postgres) schema for the Bishopric Calling Tracker. No code or SQL is committed based on this doc until it's approved.

---

## Guiding principles

1. **Event-sourced calling lifecycle.** A calling's current state is derived from the latest event in `calling_events`. The `callings` table stores identity + assignment; state lives in events. This gives us the timeline for free.
2. **One person per calling row.** "First Counselor" and "Second Counselor" are two distinct `callings` rows. If a role ever needs multiple simultaneous holders, we add a row per person — no schema change needed.
3. **Single ward, closed user set.** Every authenticated user is bishopric and sees everything. RLS is a bulkhead against un-authenticated access, not a per-user permission system (yet).
4. **Soft delete over hard delete.** Members and callings are marked inactive/archived rather than removed. Events are append-only and never edited.
5. **UUID primary keys** (`gen_random_uuid()`) — Supabase convention, safe for client-generated IDs later.

---

## Entities

### `members`

One row per person in the ward that the bishopric tracks. Manually entered.

| Column | Type | Nullable | Notes |
|---|---|---|---|
| `id` | `uuid` | no | PK, default `gen_random_uuid()` |
| `first_name` | `text` | no | |
| `last_name` | `text` | no | |
| `preferred_name` | `text` | yes | Optional — e.g. "Jim" for "James" |
| `phone` | `text` | yes | Free-form; no validation at DB level |
| `email` | `text` | yes | |
| `notes` | `text` | yes | Free-form bishopric notes about the person |
| `is_active` | `boolean` | no | default `true`; false = moved out / removed from ward |
| `created_at` | `timestamptz` | no | default `now()` |
| `updated_at` | `timestamptz` | no | default `now()`; updated by trigger |

**Deliberately NOT included in Phase 2** (open for discussion — see Open Questions):
- Membership record number (MRN)
- Address
- Date of birth, baptism date, ordination dates
- Priesthood office
- Household / family relationships
- Photo

**Indexes**:
- `idx_members_last_first` on `(last_name, first_name)` — for alphabetical list view
- `idx_members_active` on `(is_active)` — partial index `WHERE is_active = true` if the list grows

---

### `callings`

One row per calling assignment. Ties a member to a role. Lifecycle state is NOT stored here — see `calling_events`.

| Column | Type | Nullable | Notes |
|---|---|---|---|
| `id` | `uuid` | no | PK |
| `member_id` | `uuid` | no | FK → `members.id`, `ON DELETE RESTRICT` |
| `title` | `text` | no | Free-form calling name, e.g. "Elders Quorum President", "Primary Teacher — CTR 7" |
| `organization` | `text` | yes | Optional grouping, e.g. "Elders Quorum", "Primary", "Ward Council". See Open Questions — could be an enum. |
| `notes` | `text` | yes | Free-form notes specific to this calling |
| `created_at` | `timestamptz` | no | default `now()` |
| `updated_at` | `timestamptz` | no | default `now()` |

**Why not put current state here as a denormalized column?**
Because the source of truth is events. Denormalizing invites drift. If perf demands it later, we add a materialized view or a trigger-maintained `current_state` column. Not yet.

**FK behavior**: `ON DELETE RESTRICT` on `member_id` — you can't delete a member with callings. Use `is_active = false` on the member instead.

**Indexes**:
- `idx_callings_member` on `(member_id)`
- `idx_callings_organization` on `(organization)` — for grouped views

---

### `calling_events`

Append-only log of state transitions for a calling. **Never edited, never deleted** (in normal operation).

| Column | Type | Nullable | Notes |
|---|---|---|---|
| `id` | `uuid` | no | PK |
| `calling_id` | `uuid` | no | FK → `callings.id`, `ON DELETE CASCADE` |
| `state` | `calling_state` enum | no | See enum below |
| `occurred_at` | `timestamptz` | no | The date/time the event happened in real life (bishopric records "Sustained on Sunday"). Distinct from `created_at` (when they entered it into the app). |
| `notes` | `text` | yes | Free-form (e.g. "Extended by Bp. Smith", "Declined — moving out of ward") |
| `recorded_by` | `uuid` | yes | FK → `auth.users.id`. Who entered this event. Nullable to avoid breaking on user deletion. |
| `created_at` | `timestamptz` | no | default `now()` |

**Why `ON DELETE CASCADE` here (but RESTRICT on `callings.member_id`)?**
If a calling row is deleted, its history is meaningless. But deleting a member is a data-integrity concern — we force soft-delete via `is_active`.

**Indexes**:
- `idx_calling_events_calling_time` on `(calling_id, occurred_at DESC, created_at DESC)` — supports "latest event per calling" queries with a stable tiebreaker
- `idx_calling_events_state` on `(state)` — for dashboards like "how many callings are in `Extended`?"

---

## Enum: `calling_state`

Postgres enum type. Values, in canonical lifecycle order:

| Value | Meaning |
|---|---|
| `selected` | Bishopric has identified this person for the calling but not yet approached them |
| `extended` | Calling has been extended (offered) to the person |
| `accepted` | Person accepted the extended calling |
| `declined` | Person declined the extended calling — **this ends the calling row's lifecycle** (see Open Question 3) |
| `sustained` | Sustained in sacrament meeting (or ward council for some callings) |
| `set_apart` | Set apart / ordained to the calling |
| `active` | Currently serving. A separate explicit state so the bishopric can mark someone as "actively serving" independent of whether we captured the set-apart event. |
| `released` | Released from the calling |

**Why Postgres enum, not `text + CHECK constraint`?**
Enums are cheaper to store, self-documenting in the schema, and give us type safety in generated types. Downside: adding values requires `ALTER TYPE`, which is straightforward. We're not going to add values often — this list mirrors the brief.

**Terminal states**: `declined` and `released` end a calling's lifecycle. New events after these are technically allowed by the schema (append-only), but the UI won't create them. If we ever need hard enforcement, a trigger can reject events after a terminal state.

**Skipping states is allowed.** The bishopric may not always record every step. `selected → sustained` (skipping `extended`, `accepted`, `set_apart`) is legal. This is by design — the app tracks reality, not a workflow enforcement engine.

---

## RLS (Row-Level Security)

**Approach for Phase 2**: Any authenticated user has full access to all three tables. Anonymous users have no access.

```
-- pseudocode
CREATE POLICY "authenticated read"   ON members       FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "authenticated write"  ON members       FOR ALL    USING (auth.role() = 'authenticated');
-- same for callings, calling_events
```

**Why so permissive?**
- Every user is bishopric (manually provisioned by us in Supabase dashboard)
- There's no "regular member" role to protect against
- Adding per-role RLS now is speculative; we'd design it wrong

**Future evolution** (post-Phase 2, if needed):
- A `bishopric_roles` table with `user_id` + role (`bishop`, `counselor`, `clerk`, `exec_secretary`)
- Policies that restrict writes to certain roles

Not building any of that now.

---

## Triggers

Two lightweight triggers:

1. **`set_updated_at`** — Before UPDATE on `members`, `callings`, set `updated_at = now()`.
2. *(deferred)* Enforce append-only on `calling_events`. Postgres has no built-in "no updates/deletes" — we'd need a `BEFORE UPDATE/DELETE` trigger that raises. Skipping for Phase 2 because RLS + client discipline is enough for a private tool; add later if we care.

---

## What we do NOT model (yet)

- **Bishopric users / roles.** Uses Supabase `auth.users` directly. No `profiles` table.
- **Notifications / reminders.** Phase 3.
- **Attachments** (photos, docs). Phase 3+.
- **Historical import.** Bishopric starts fresh; no import of prior calling history.
- **Multiple wards.** Single-ward tool by design.

---

## Open Questions (need answers before writing SQL)

These are cheap to argue about now, expensive later.

### Q1 — Member fields

The `members` table above is deliberately minimal (name, phone, email, notes, active flag). Do you want any of these in Phase 2, or defer them all?
- **Membership record number (MRN)** — useful for cross-referencing with LCR. Just a `text` column.
- **Date of birth** — needed for age-based calling eligibility (e.g. Aaronic priesthood age).
- **Priesthood office** (`deacon`, `teacher`, `priest`, `elder`, `high_priest`, `none`) — often relevant to calling decisions.
- **Sex / gender** — relevant for callings restricted by sex.
- **Household grouping** — link spouses/families. Nontrivial; probably Phase 3.
- **Address** — probably not needed in-app; bishopric has LCR for that.

My recommendation: **add `date_of_birth`, `priesthood_office`, and `sex` now**. These directly inform calling decisions and are cheap. Skip MRN and household for now.

### Q2 — `organization` field on `callings`

Free-form `text` or a fixed set of church organizations (`elders_quorum`, `relief_society`, `primary`, `young_men`, `young_women`, `sunday_school`, `bishopric`, `ward_council`, `other`)?

- **Free text**: flexible, no schema churn when a new sub-org appears
- **Enum**: consistent, queryable, but "Primary — CTR 7" vs "Primary — Nursery" both roll up under `primary`

My recommendation: **`text` for now**, and revisit if we build dashboards that group by org. The `title` column already carries specificity.

### Q3 — What does `declined` mean for the calling row?

When a person declines an extended calling, options:
- **(a) Terminal state.** The `callings` row is closed. If the bishopric wants to offer the same role to someone else, they create a NEW `callings` row with a new `member_id`. Clean audit trail.
- **(b) Reassignable.** The `callings` row stays; a new `calling_events` entry can be recorded, and later the row could be reassigned to another member. Ugly — `member_id` on `callings` becomes a lie.

My recommendation: **(a)**. Each calling row is one attempt to fill a role with one person. If it fails, start over.

### Q4 — Timezone of `occurred_at`

`timestamptz` stores UTC and displays in the client's zone. But bishopric records dates ("Sustained on Sunday March 3rd"), not times. Should `occurred_at` be a `date` instead of `timestamptz`?

My recommendation: **`timestamptz`** — keeps the option open for time-of-day precision without a schema change; UI can show date-only.

### Q5 — Deleting members

Currently `ON DELETE RESTRICT` — you can never hard-delete a member with any callings. Is that too strict? Alternatives:
- `CASCADE` deletes the callings and their events (destructive; loses history)
- `SET NULL` on `member_id` (orphans callings; probably confusing)

My recommendation: **keep RESTRICT**. Soft-delete via `is_active = false` is the correct path.

### Q6 — Uniqueness constraints

Should any of these be enforced?
- One "active" calling per person? (i.e. a member can hold only one calling at a time) — **NO**. Members frequently have multiple callings (e.g. Primary teacher + Ward Choir Director).
- One holder per calling title? (i.e. only one "Elders Quorum President" at a time) — **Possibly**, but hard to express in SQL because "active" is derived from events. Enforce in UI, not DB.

My recommendation: **no DB-level uniqueness constraints** on business rules. Only PK uniqueness.

---

## Summary of proposed final shape (assuming my recommendations)

```
members (
  id uuid PK,
  first_name text, last_name text, preferred_name text?,
  phone text?, email text?, notes text?,
  date_of_birth date?, sex text?, priesthood_office text?,
  is_active bool,
  created_at, updated_at timestamptz
)

callings (
  id uuid PK,
  member_id uuid FK members RESTRICT,
  title text, organization text?, notes text?,
  created_at, updated_at timestamptz
)

calling_events (
  id uuid PK,
  calling_id uuid FK callings CASCADE,
  state calling_state,
  occurred_at timestamptz,
  notes text?,
  recorded_by uuid FK auth.users SET NULL,
  created_at timestamptz
)

TYPE calling_state ENUM (
  'selected','extended','accepted','declined',
  'sustained','set_apart','active','released'
)
```

Total: 3 tables, 1 enum, 2 triggers (`set_updated_at` on members + callings), permissive-auth RLS on all three.
