# Dornevi ERP — PMS Phase 2 Housekeeping Architecture

**Scope:** PMS Phase 2 / Step 1, Housekeeping / Kat Hizmetleri.  
**Status:** Implementation specification; implementation and deployment have not been performed.  
**Date:** 2026-09-09.  
**Audience:** The implementing engineer or Claude agent, PMS operations, and PostgreSQL/Supabase security reviewers.

The terms MUST, MUST NOT and REQUIRED define acceptance criteria. Phase 1 is CLOSED, LIVE and hash-locked. All future database changes described here belong in a new Phase 2 migration. This document contains architecture contracts, not executable implementation code.

> **Sole authority.** This Markdown file is the sole authoritative Housekeeping architecture baseline. Earlier chat summaries, drafts and Astra intermediate outputs are non-authoritative and MUST NOT be used as implementation input. Where any other text disagrees with this file, this file wins. Do not create a competing Housekeeping architecture file; amend this one.

Related references: [[MIGRATION-GUVENLIK-STANDARDI]], [[2026-09-07-pms-faz1-yayin-manifesti]], [[#11. Concurrency Model]], [[#22. Test Strategy]], [[#24. Rollback / Feature Disable]].

## 1. Executive Architecture

Build one historical cleaning-task table, a small command API, database-maintained room readiness, and transactional checkout automation. Keep the existing vanilla HTML/JavaScript and Supabase architecture.

**Decision:** Add `public.pms_housekeeping_gorevleri`; allow at most one unfinished task per room. Store completed and cancelled attempts permanently as operational history.

**Reason:** Room flags cannot represent ownership, interrupted cleaning, elapsed work, cancellation or inspection attribution. A separate task row is necessary; a separate event-sourcing platform is not.

**DB enforcement:** Composite foreign keys, an unfinished-task partial unique index, controlled RPCs, row-transition guards, current-cycle room linkage, and deferred cross-table constraint triggers.

**Failure prevented:** Duplicate work, lost history, stale completion making a newly occupied room appear inspected, and frontend-only state enforcement.

The design has three responsibilities, not three independently writable statuses:

1. `pms_housekeeping_gorevleri.durum` records the cleaning workflow.
2. `pms_odalar.temizlik_durumu` is the database-maintained readiness value consumed by existing check-in.
3. `pms_odalar.temizlik_gorevi_id` identifies which current task is allowed to support that readiness value.

The room row is the serialization point. A task transition and its room projection either both commit or both roll back. Historical tasks never overwrite current room readiness.

P0 acceptance conditions are tenant isolation, sealed DML paths, preservation of Phase 1 occupancy invariants, consistent lock ordering, deterministic checkout replacement, and transactional audit. P1 concerns are efficient mobile queues, explicit overdue indicators and bounded query costs.

This specification was prepared from read-only inspection of the permitted local PMS files and their necessary direct dependencies. It does not claim a fresh production verification. The only artifact authorized in this documentation task is `docs/PMS-FAZ2-HOUSEKEEPING-ARCHITECTURE.md`.

## 2. Existing PMS Integration

### Verified source contracts

| Inspected source | Relevant contract |
|---|---|
| `docs/kurulum/2026-09-06-pms-faz1-oda-tipleri-odalar.sql` | UUID rooms; `otel_id` enum; room `(id, otel_id)` unique key; usage and cleanliness enums; authenticated room DML |
| `docs/kurulum/2026-09-06-pms-faz1-adim2-misafir-rezervasyon.sql` | Reservation/assignment composite hotel FKs; assignment exclusion constraint; actual source-assignment structure |
| `docs/kurulum/2026-09-06-pms-faz1-adim3-checkin-checkout.sql` | Invoker check-in/out; reservation → assignment → room locks; named deferred consistency constraints |
| `pms-oda-plani.html` | Direct cleanliness PATCH currently exists; five bulk reads; occupancy lookup still contains a planned-end-date filter |
| `auth-guard.js`, `nav-drawer.js`, `ortak.js` | Existing permission-aware navigation, login integration and HTTP write helper behavior |
| Targeted sections of `docs/kurulum/2026-09-07-post-pms-faz1-sema-dokumu.sql` | Current auth helpers, employee schema, audit schema and checkout function |
| Directly relevant folio-trigger section of `docs/kurulum/2026-09-06-pms-faz1-adim4-folio.sql` | Automatic internal record creation already uses a definer trigger; checkout is not replaced by folio |
| `docs/kurulum/MIGRATION-GUVENLIK-STANDARDI.md`, `SABLON-yeni-migration.sql`, `scripts/migration-guvenlik-kontrol.mjs` | Explicit ACLs, RLS, definer pinning, function sweeps, checker limits |
| Post-PMS fingerprint, function ACL cleanup, event-trigger and database-level baseline documents | Live baseline expectations and zero Realtime publication tables |

Archived migration headers still describe release-candidate status. They are historical text, not evidence that Phase 1 is undeployed. Use the supplied live status and later post-PMS baseline documentation.

### Core state contracts that remain authoritative

- Room usage: `bos`, `dolu`, `bloke`, `ariza`.
- Room cleanliness: `temiz`, `kirli`, `temizleniyor`, `kontrol_edildi`.
- Checkout sets usage to `bos` and cleanliness to `kirli`.
- Check-in accepts only an active, vacant room whose cleanliness is `temiz` or `kontrol_edildi`.
- Actual occupancy means an active assignment linked to a `giris_yapildi` reservation. An expired planned departure date does not end occupancy.
- Phase 1 prevents occupied rooms from being blocked or marked faulty before checkout.
- Normal checkout retains the assignment as historical evidence.
- Reservation capacity, assignment date overlap, folio, charges, payments and bar-to-folio logic retain their existing ownership.

**P0 integration detail:** `pms_check_out` updates the room first, then the reservation. It defers only `pms_tutarlilik_oda`, `pms_tutarlilik_rezervasyon`, and `pms_tutarlilik_atama`. New housekeeping consistency constraints therefore MUST be `DEFERRABLE INITIALLY DEFERRED`; otherwise a reservation AFTER trigger cannot repair the legitimate intermediate checkout state.

The inspected employee model uses `kullanicilar.id` as ERP identity and `auth_user_id` as Supabase identity. Hotel access is the employee's `otel_id` or `tum_oteller = true`. There is no inspected normalized employee-hotel membership table to reference.

The supplied baseline is 75 public tables, 234 policies and 40 restrictive policies, with zero RLS-disabled tables, unpinned definers and anonymous table privileges. The later ACL cleanup records anonymous PMS EXECUTE as zero. The database-level baseline records zero published Realtime tables.

## 3. Key Architectural Decisions

| Question | Binding answer |
|---|---|
| 1. Separate housekeeping task/history table? | **Yes**, one task row per cleaning attempt. |
| 2. Checkout automatically creates a task? | **Yes**, while module automation is enabled. |
| 3. Same transaction as checkout? | **Yes**, including task replacement, room state and audit. |
| 4. Supervisor inspection policy? | **Optional**, fixed in Step 1; no hotel setting now. |
| 5. Can `temiz` be checked in before inspection? | **Yes**, subject to all existing occupancy/assignment checks. |
| 6. Maximum active tasks per room? | **One**, where active means `bekliyor` or `temizleniyor`. |
| 7. Direct REST/DML task-state changes? | **No** for application roles. Purpose-specific RPCs are required. |
| 8. Worker self-claim? | **Yes**, eligible worker, unassigned waiting task, available room. |
| 9. Supervisor reopening? | **Yes as a linked successor**, never by rewinding the completed row. |
| 10. Maintenance/technical defects? | **Separate future module**; housekeeping only reacts to room availability. |
| 11. Task versus room authority? | Task owns workflow; the current task atomically maintains the existing room-readiness projection. The room pointer prevents historical tasks from acting. |
| 12. Completion versus check-in race? | Shared room `FOR UPDATE` serialization and locked readiness rechecks. |
| 13. Duplicate prevention? | Room lock, active-task partial uniqueness, permanent creation key, checkout source uniqueness and successor uniqueness. |
| 14. Exact DB protections? | ACL revocation; operation-specific RLS; restrictive hotel boundary; FKs/CHECKs/uniques; immutable/transition/DML guards; locked RPCs; deferred final-row consistency; transactional audit. |

**Decision:** Inspection is a refinement of successful cleaning, not an additional active task.

**Reason:** Optional inspection must not occupy the single unfinished-work slot or prevent a hotel from checking in a clean room.

**DB enforcement:** `tamamlandi` is outside the active index, inspection requires the current room pointer and vacancy, and check-in retires that pointer.

**Failure prevented:** Old pending inspections accumulating as active work or certifying a later guest's room.

**Decision:** No new framework, queue service, cron job, Realtime subscription, maintenance schema or parallel authorization store is required in Step 1.

**Reason:** The bounded per-room working set and existing database transaction model already support the operational requirements.

**DB enforcement:** Synchronous command boundaries and the constraints defined below.

**Failure prevented:** Extra moving parts without stronger correctness.

## 4. Database Contract

### 4.1 Main table

Table: **`public.pms_housekeeping_gorevleri`**. New task IDs use generated UUIDs; no human task-number sequence.

| Column | Type | Required/default | Contract |
|---|---|---|---|
| `id` | `uuid` | NOT NULL, generated PK | Immutable task identity |
| `otel_id` | `public.otel_id` | NOT NULL | Immutable tenant |
| `oda_id` | `uuid` | NOT NULL | Immutable room |
| `gorev_tipi` | `text` | NOT NULL | Immutable type; three permitted values |
| `durum` | `text` | NOT NULL, `bekliyor` | Five-state lifecycle |
| `kaynak_atama_id` | `uuid` | Conditional | Immutable source stay/checkout assignment |
| `onceki_gorev_id` | `uuid` | Optional | Immutable predecessor for replacement/rework |
| `atanan_kullanici_id` | `uuid` | Optional while waiting | ERP `kullanicilar.id`; frozen when started |
| `oncelik` | `smallint` | NOT NULL, `2` | `1` urgent, `2` normal, `3` low |
| `notlar` | `text` | Optional | Operational text, trimmed, maximum 1,000 characters |
| `hedef_zamani` | `timestamptz` | Optional | Actual deadline, not future activation |
| `baslama_zamani` | `timestamptz` | Conditional | Write-once actual start |
| `bitis_zamani` | `timestamptz` | Conditional | Write-once successful cleaning completion |
| `kontrol_zamani` | `timestamptz` | Conditional | Write-once successful inspection |
| `kontrol_eden` | `uuid` | Conditional | ERP inspector ID |
| `iptal_zamani` | `timestamptz` | Conditional | Write-once cancellation time |
| `iptal_nedeni` | `text` | Conditional | Controlled cancellation reason code |
| `olusturma_kaynagi` | `text` | NOT NULL, `kullanici` | Immutable creation origin: `kullanici`, `checkout`, `sistem` |
| `olusturan` | `uuid` | Conditional | ERP creator; required for `kullanici`, NULL permitted only for `sistem` |
| `olusturma_tarihi` | `timestamptz` | NOT NULL, server time | Immutable creation time |
| `guncelleme_tarihi` | `timestamptz` | NOT NULL, server time | Last actual task mutation |
| `surum` | `bigint` | NOT NULL, `1` | Positive optimistic version |
| `istek_anahtari` | `uuid` | NOT NULL | Immutable creation request key |
| `istek_ozeti` | `text` | NOT NULL | Immutable server-computed creation fingerprint |
| `son_islem_anahtari` | `uuid` | NOT NULL | Most recent effective command key |
| `son_islem_ozeti` | `text` | NOT NULL | Most recent effective command fingerprint |

Creation sets the last-command receipt to the creation command. Subsequent actual mutations replace only the last-command fields. [[#12. Idempotency]] defines their bounded replay guarantee, and [[#12. Idempotency]] section 12.4 defines how internal operations satisfy the NOT NULL receipt columns.

#### 4.1.1 Creation origin and actor

**Decision:** `olusturan` is nullable and paired with an immutable `olusturma_kaynagi`. Do **not** create a sentinel/system ERP user, and do **not** reject a legitimate system or administrative room-lifecycle transition merely because `auth.uid()` is NULL.

**Reason:** `kullanicilar.id` is a real employee identity. Fabricating one to satisfy NOT NULL would place a false actor into operational history; rejecting actor-less transitions would make ordinary administrative room maintenance fail.

**DB enforcement:** CHECK constraints binding origin to actor presence; immutable origin; audit remains authoritative for transaction and database-actor attribution.

**Failure prevented:** Fake attribution, unsatisfiable NOT NULL on producer paths, and blocked room lifecycle work.

| `olusturma_kaynagi` | Created by | `olusturan` |
|---|---|---|
| `kullanici` | Manual supervisor command, rework, handover | **MUST NOT be NULL** |
| `checkout` | Reservation checkout producer | Actual ERP actor when one exists; **never fabricated** |
| `sistem` | Room lifecycle producer and other sealed internal creation | **MAY be NULL** |

Required CHECK constraints:

- `olusturma_kaynagi in ('kullanici','checkout','sistem')`.
- `olusturma_kaynagi <> 'kullanici' or olusturan is not null`.
- `olusturma_kaynagi = 'checkout'` if and only if `gorev_tipi = 'cikis_temizligi'`.
- `olusturma_kaynagi = 'sistem'` implies `gorev_tipi = 'ekstra_temizlik'` and no assignee at creation.

`olusturma_kaynagi` joins the always-immutable set. Three values are the smallest set that distinguishes the three creation authorities this design already has; no further origin values are introduced.

Credentials, JWTs and claimed actor identities are never copied into the task row. The audit row carries `actor_user_id`, `actor_role` and `pg_current_xact_id()` and remains the authority for who performed the transaction. A `checkout` task created by a valid reception session records that reception employee as `olusturan`; if a checkout ever occurs without a resolvable ERP actor, `olusturan` stays NULL while audit still records the database actor. That is deliberately weaker than inventing an employee.

No separate `aktif` flag, floor, room number, guest information, employee names or separate assignment-history table is added. Assignment changes are audited. The assignee is frozen after start, and only that worker can complete, so separate start/completion actor columns would duplicate that contract. Inspector and creator remain explicit.

### 4.2 Keys and foreign keys

All new business-reference FKs use `ON UPDATE RESTRICT` and `ON DELETE RESTRICT`. Do not cascade historical tasks away.

| Name | Contract |
|---|---|
| `pms_housekeeping_gorevleri_pkey` | Primary key `(id)` |
| `pms_housekeeping_gorevleri_id_oda_otel_key` | Unique `(id, oda_id, otel_id)` |
| `pms_housekeeping_oda_fk` | `(oda_id, otel_id)` → `pms_odalar(id, otel_id)` |
| `pms_oda_atamalari_id_oda_otel_key` | New target unique `(id, oda_id, otel_id)` on assignments, added by Phase 2 |
| `pms_housekeeping_kaynak_atama_fk` | `(kaynak_atama_id, oda_id, otel_id)` → assignment target key |
| `pms_housekeeping_onceki_gorev_fk` | `(onceki_gorev_id, oda_id, otel_id)` → task target key |
| User FKs | Assignee, creator and inspector → `kullanicilar(id)` |

Nullable composite references use normal MATCH SIMPLE semantics: NULL source/predecessor means no relationship. A populated reference must match room and hotel. The source FK deliberately prevents moving/deleting a source assignment after it supports housekeeping history.

Add **`pms_odalar.temizlik_gorevi_id uuid NULL`**, with `pms_odalar_temizlik_gorevi_fk`: `(temizlik_gorevi_id, id, otel_id)` → task `(id, oda_id, otel_id)`. This is the only room schema field added for current-cycle identity. No redundant `(id, otel_id)` unique key is needed on tasks because all task relationships use the three-column target.

### 4.3 CHECK rules

- `durum` is exactly one of `bekliyor`, `temizleniyor`, `tamamlandi`, `kontrol_edildi`, `iptal`.
- `gorev_tipi` is exactly one of `cikis_temizligi`, `konaklama_temizligi`, `ekstra_temizlik`.
- `oncelik` is 1–3; `surum` is positive.
- Optional text uses NULL instead of an empty/whitespace-only value; stored notes equal their trimmed representation and have length at most 1,000.
- Fingerprints are exactly 64 lowercase hexadecimal characters: SHA-256 of the canonical server-normalized command envelope.
- All populated timestamps are finite. Creation ≤ start ≤ completion ≤ inspection where applicable; cancellation is not before creation or an existing start; last update is not before any task event timestamp.
- A deadline may already be overdue at creation. Do not require it to be after the server's current time.
- `onceki_gorev_id` cannot equal `id`.
- `cikis_temizligi` and `konaklama_temizligi` require a source assignment.
- Inspector/time must both be NULL or both be populated; a populated inspector must differ from the assignee.

| Status | Assignee | Start | Completion | Inspection/inspector | Cancellation/reason |
|---|---|---|---|---|---|
| `bekliyor` | Optional | NULL | NULL | NULL | NULL |
| `temizleniyor` | Required | Required | NULL | NULL | NULL |
| `tamamlandi` | Required | Required | Required | NULL | NULL |
| `kontrol_edildi` | Required | Required | Required | Required | NULL |
| `iptal` | Retain if present | Retain if present | NULL | NULL | Required |

For a cancelled task with a start time, the assignee is required. Cancelling completed work is invalid; create a successor instead.

Permitted cancellation codes are `operasyonel`, `devir`, `yeniden_temizlik`, `cikis_ile_yenilendi`, `oda_bloke`, `oda_ariza`, `oda_pasif`. User cancellation accepts only `operasyonel`; handover uses `devir`; the remaining codes are selected by sealed internal operations. For operational cancellation, a nonempty operational explanation is required and stored in `notlar`, not copied to audit details.

### 4.4 Immutable and system fields

Always immutable: task identity, hotel, room, type, creation origin, source assignment, predecessor, creator, creation timestamp/key/fingerprint. Start/completion/inspection/cancellation timestamps are write-once. A predecessor must already exist and be the current task in an allowed replacement operation; immutable predecessors therefore cannot form a later cycle.

After start, the assignee is frozen. Completed/inspected/cancelled rows reject all ordinary edits. `tamamlandi` has exactly one permitted refinement: inspection, changing only status, inspector/time, version, update time and the last-command receipt.

#### 4.4.1 Shared hotel-immutability convention

`pms_housekeeping_gorevleri` MUST also carry the existing shared protection:

```sql
create trigger phase0_otel_degismez before update of otel_id
  on public.pms_housekeeping_gorevleri
  for each row execute function phase0_private.otel_degismez();
```

**Reason:** every updateable Phase 1 PMS table carries it. The two tables that do not (`pms_folio_hareketleri`, `pms_folio_odemeler`) are append-only, where UPDATE is structurally impossible; the task table is deliberately updateable, so the exemption does not apply.

Do **not** replace this with a second custom hotel-immutability mechanism. The housekeeping transition guard still enforces its own immutable-field contract covering identity, room, type, origin, source, predecessor and creation fields — the shared Phase 0 trigger is defence in depth on top of it, in the same way the append-only tables carry both a privilege layer and a trigger layer.

This adds one to the `phase0_otel_degismez` counter; see 17.5.

Capture one `clock_timestamp()` value after locking for each effective operation. Use it consistently for that operation's task stamps and update time. Do not use a client timestamp or a transaction-start timestamp that predates a lock wait. Room `guncelleme_tarihi` remains its existing field and is not an optimistic lock token.

### 4.5 Unique and query indexes

The mandatory unique and nonunique index definitions are fixed in [[#21. Performance / Index Strategy]]. Every unfinished task is covered by a non-deferrable partial unique index. PostgreSQL cross-table CHECK expressions are not used; FKs and constraint triggers own cross-table facts.

## 5. Task Types

**Decision:** Three CHECK-constrained text types; no new PostgreSQL enum and no inspection task type.

**Reason:** Types express why cleaning is required. Inspection certifies an existing cleaning attempt rather than creating another work order.

**DB enforcement:** Type CHECK, source-assignment FK, insert guard and purpose-specific creation RPCs.

**Failure prevented:** Arbitrary type drift, untraceable turnover tasks and an inspection queue competing with cleaning uniqueness.

| Type | Creation authority | Preconditions and source |
|---|---|---|
| `cikis_temizligi` | Checkout trigger only | Actual reservation checkout; exact historical active assignment; vacant dirty room |
| `konaklama_temizligi` | Housekeeping `tam` | Room currently occupied by the active assignment of a checked-in reservation; source required |
| `ekstra_temizlik` | Housekeeping `tam`, rework/handover, or dirty-room release trigger | Vacant/blocked backlog uses no source; occupied work requires the exact current stay source |

Source identity is resolved by the database. Manual creation requires an active room and does not accept a caller-selected source assignment. It requires `beklenen_kullanim_durumu`, checked again on the locked room, so a stale vacant-room intention cannot silently become service for a newly checked-in guest. For extra work in a vacant room, source is NULL; the predecessor still preserves rework lineage. Automatic checkout still records required waiting work for an inactive room; physical execution remains blocked until the room is active again.

Creating any task means cleaning is required now and immediately invalidates clean readiness. `hedef_zamani` is a completion target. Future scheduled visits that should leave the room ready are outside this task contract.

Step 1 has no automatic daily recurrence. Supervisors create stayover work explicitly. A batch UI submits bounded per-room commands with independent request keys; it does not require a new scheduler or job table.

## 6. Housekeeping State Machine

### 6.1 Allowed transitions

Assignment is a field, not an `atandi` state. Active/unfinished means only `bekliyor` or `temizleniyor`.

| From | Command | To | Actor and prerequisites |
|---|---|---|---|
| No task | Create | `bekliyor` | Supervisor or verified automatic producer; no other unfinished task |
| `bekliyor`, unassigned | Claim | `bekliyor`, self-assigned | Eligible `kayit` worker; room active and usable |
| `bekliyor`, assigned to self | Release | `bekliyor`, unassigned | Same active worker |
| `bekliyor` | Assign/reassign/unassign | `bekliyor` | `tam`; target eligible if populated |
| `bekliyor` | Start | `temizleniyor` | Assigned eligible worker; current pointer; room/type context still valid |
| `temizleniyor` | Complete | `tamamlandi` | Same assigned eligible worker; current pointer; room available for work |
| `tamamlandi` | Inspect | `kontrol_edildi` | `tam`, different from cleaner; current pointer; active vacant room |
| `bekliyor` or `temizleniyor` | Cancel | `iptal` | `tam` or a verified lifecycle invalidator |

Only the listed status transitions are valid. The insert guard rejects starting in any other state, even if supplied timestamps look plausible. RPC retries that make no change are not transitions.

`iptal` and `kontrol_edildi` are fully terminal. `tamamlandi` is cleaning-terminal and can only be refined to inspected. It does not remain active while inspection is optional.

Priority/deadline edits are available to supervisors while waiting. Supervisors can edit notes on any unfinished task; workers can edit notes only on their own unfinished task. No actor can backdate events, remove a start stamp, or complete another person's task merely because they have `tam`.

### 6.2 Claim, reassignment and handover

- Claim succeeds only when assignee is NULL. A worker cannot steal a task or claim a task assigned to somebody else.
- Release succeeds only for one's own waiting task.
- Reassignment is allowed only while waiting and requires the expected version.
- Start freezes the assignee. A running-task handover cancels the old attempt and creates an unassigned `ekstra_temizlik` successor in the same transaction, making the room dirty. Assignment of that successor is a separate normal command.
- A supervisor can plan/reassign waiting work in blocked/fault rooms, but a worker cannot claim/start it until released.

### 6.3 Reopening and failed inspection

**Decision:** Reopening creates a successor; it never rewinds historical state.

**Reason:** Reusing the old row would erase completed work and create ambiguous timestamps and replay semantics.

**DB enforcement:** `pms_housekeeping_yeniden_ac` locks the room and predecessor, requires current completed/inspected work and vacancy, and inserts one `ekstra_temizlik` successor. Predecessor uniqueness prevents repeated reopening even with another request key.

**Failure prevented:** Double rework, overwritten inspection evidence and stale commands reopening an obsolete room cycle.

A failed inspection uses this same rework command with a required explanation. The previous task remains `tamamlandi` or `kontrol_edildi`; the successor becomes current and the room becomes dirty. After another guest checks in, servicing that guest is new stayover/extra work, not reopening the prior turnover task.

## 7. Room State Integration

### 7.1 Authoritative relationship

**Decision:** Keep `pms_odalar.temizlik_durumu` as the Phase 1 readiness contract, maintained only by controlled current-cycle operations.

**Reason:** Check-in already reads and locks this field. Replacing it with frontend task calculations would split authority and expand core changes.

**DB enforcement:** Room pointer FK, sealed room-write guard, task transition guard, room locks and deferred final-row consistency checks on both tables.

**Failure prevented:** Room/task drift and old task completion certifying a newer cleaning cycle.

| Event | Task result | Room result |
|---|---|---|
| A. Checkout | New `cikis_temizligi`; unfinished prior attempt cancelled | `bos` + `kirli`, pointer to new task |
| B. Create task | `bekliyor` | `kirli`, pointer to new task; usage unchanged |
| C. Claim | Waiting, self-assigned | Remains `kirli` |
| D. Start | `temizleniyor` | `temizleniyor` |
| E. Complete | `tamamlandi` | `temiz` |
| F. Inspect | `kontrol_edildi` | `kontrol_edildi` |
| G. Cancel | `iptal` | `kirli`; pointer may retain this cancelled current attempt |
| H. Reassign | Waiting, new assignee | Remains `kirli` |

Cancellation never restores a pre-task clean value. Once cleaning was required or interrupted, only successful new work can certify cleanliness.

### 7.2 Commit-time invariants

Assign stable names H1–H10 in implementation tests:

1. **H1:** At most one unfinished task per hotel/room.
2. **H2:** Every unfinished task is the task referenced by its room.
3. **H3:** A current waiting task requires room `kirli`.
4. **H4:** A current running task requires room `temizleniyor`, and vice versa.
5. **H5:** A current completed task requires room `temiz`.
6. **H6:** A current inspected task requires room `kontrol_edildi`.
7. **H7:** A current cancelled task requires room `kirli`.
8. **H8:** A current pointer always identifies a task for the same room and hotel.
9. **H9:** A historical non-current task cannot make a transition affecting readiness or inspection.
10. **H10:** Running work cannot remain committed on an inactive, blocked or fault room.

Dirty rooms with no task are valid backlog. Clean/inspected rooms with no pointer are valid after check-in or from the accepted Phase 1 baseline. A room cannot be `temizleniyor` without a running current task once Phase 2 is activated.

Cross-table constraint functions read the final persisted task/room rows by key, not the obsolete `NEW` snapshot of an earlier queued event. They run with sufficient privileges to see the invariant's rows despite caller RLS. Check both old and new affected references if a room pointer changes.

### 7.3 Check-in and occupancy

On `bos` → `dolu`, the new room guard requires the old locked cleanliness to be `temiz` or `kontrol_edildi`, requires the incoming cleanliness to be unchanged, and rejects an incoming caller-changed pointer. The guard then retires the pointer itself. Phase 1 keeps enforcing reservation/assignment/doluluk consistency.

Retiring a completed pointer does not rewrite the historical task. A later inspection of that task fails as stale. Occupied stayover cleaning can set room cleanliness to dirty/cleaning/clean while usage stays `dolu`; housekeeping never changes usage to vacant.

### 7.4 Initial activation

The new migration MUST abort if any existing room is `temizleniyor` without a Phase 2 task adoption path. For Step 1, choose the simpler cutover: complete or stop ongoing legacy cleaning through an explicitly approved operational process before migration, and require zero legacy `temizleniyor` rooms at the activation precondition. Do not fabricate start times or assignees in a migration.

Existing dirty rooms remain visible as `Kirli — görev yok` and receive supervisor-created extra tasks after enablement. Existing clean/inspected rooms keep their readiness with a NULL pointer. No bulk task-history invention or reservation backfill is required.

## 8. Checkout Integration

### 8.1 Selected extension point

**Decision:** Add an ordinary AFTER UPDATE trigger on `pms_rezervasyonlar`, firing only for actual `giris_yapildi` → `cikis_yapildi` transitions. Name it `pms_housekeeping_cikis_uret`.

**Reason:** The event identifies an actual checkout and its stay. It fires in the existing transaction after the room has been dirtied.

**DB enforcement:** Transition predicate, source assignment validation, inherited core locks, natural checkout-source uniqueness, active-task uniqueness and final consistency checks.

**Failure prevented:** Checkout without cleaning work, room-only transition misclassification and omitted frontend follow-up requests.

| Option | Decision |
|---|---|
| A. Replace `pms_check_out` through a new migration | Technically valid, but not selected; avoid copying a live core function to add this concern |
| B. Reservation AFTER trigger | **Selected**; smallest reliable transactional integration |
| C. Separate frontend-called RPC | Rejected as authoritative integration; independent requests cannot guarantee atomic checkout and task creation |

### 8.2 Transaction algorithm

1. Existing checkout validates and locks the reservation, its exact active assignment and room.
2. Existing checkout writes room `bos` + `kirli`. The always-on room invalidator cancels any current unfinished attempt with `cikis_ile_yenilendi` and retains its cancelled pointer for the producer. If the current task was already terminal, it retires that pointer without changing history.
3. Reservation transitions to checked out with the existing actor/time stamps.
4. The new trigger verifies the authenticated active ERP actor, `pms_rezervasyon/kayit`, actual hotel access, exactly one source assignment, and room vacancy/dirtiness.
5. Lock existing current/unfinished housekeeping rows after the room. Take the shared module-state lock defined in [[#11. Concurrency Model]].
6. Read the current cancelled predecessor left by room invalidation, if any; verify `cikis_ile_yenilendi`, the exact current checkout source assignment, room and hotel. Do not cancel it twice or overwrite its last receipt/stamps. Any unfinished task remaining at this point is an integrity error, because room invalidation was required to retire it first.
7. When enabled, create one unassigned waiting `cikis_temizligi`, normal priority, no deadline, source assignment populated, and predecessor populated only when an unfinished task was superseded. Set its pointer on the room.
8. When disabled, do not create a new task; clear the room pointer after necessary invalidation and leave the room vacant/dirty.
9. Audit and deferred checks either commit with checkout or roll the whole transaction back.

Source selection never uses planned end date. The checkout trigger does not lock a different reservation or assignment after acquiring the room. The source rows are those already locked by Phase 1.

A stayover task is never relabelled as checkout cleaning. Even if it completed just before checkout, a fresh turnover cleaning requirement is created.

### 8.3 Retry and exception behavior

The checkout source index covers **all** checkout-origin tasks, including completed and cancelled history. The internal producer checks that source under the room lock before making side effects. Finding an existing valid source task returns an internal no-op; it must not repoint the room to historical work. A mismatched source/hotel/room is an integrity error, not success.

Generate a random server creation key on the first checkout-task insertion. The permanent source-assignment unique index, not a predictable client-key namespace, provides automatic checkout idempotency. Retries find that source before generating another key. Only the sealed producer can choose this automatic source.

The existing public `pms_check_out` still rejects a repeated call on a checked-out reservation. An ambiguous client response is reconciled by reading the reservation's authoritative status. This design makes task production retry-safe; it does not falsely claim to change the existing RPC's response semantics.

No catch-all exception suppression is allowed. With production enabled, a task insertion/audit/consistency failure rolls back checkout. [[#24. Rollback / Feature Disable]] defines the operational escape from a defective producer.

## 9. Inspection Policy

**Decision:** Inspection is optional in Step 1. Do not introduce a hotel inspection setting.

**Reason:** Existing live check-in accepts both clean and inspected rooms. Requiring inspection would change hotel readiness policy, staffing dependencies and availability semantics.

**DB enforcement:** Completion sets `temiz`; inspection sets `kontrol_edildi`; Phase 1 eligibility remains both values. Inspection requires `tam`, a different inspector from the cleaner, a current completed task and an active vacant room.

**Failure prevented:** Unplanned check-in outages and a UI-only policy that disagrees with PostgreSQL.

- `temiz` means the assigned worker successfully completed the current cleaning attempt.
- `kontrol_edildi` means a different authorized supervisor verified that same attempt while the room was still vacant.
- A clean, uninspected room is check-in eligible.
- A successful check-in retires the current-cycle pointer; its old completed task is no longer an actionable pending inspection.
- Pending inspection means a currently referenced `tamamlandi` task on an active vacant room. It does not mean every historical completed task.
- A one-person team can release a room as clean, but cannot label its own work independently inspected.

A future mandatory-inspection policy requires a separately approved migration and database check-in guard changes. It is not hidden behind a Step 1 frontend toggle.

## 10. Blocked / Fault Room Behavior

**Decision:** Room availability gates physical housekeeping; housekeeping does not own availability or repairs.

**Reason:** A worker must not release an unsafe room, and changing a usage flag cannot silently certify cleaning.

**DB enforcement:** Room lifecycle invalidation, locked command preconditions and H10. Preserve the existing prohibition on directly blocking an occupied room.

**Failure prevented:** Completing work after a room becomes inaccessible or making a faulty room available through a housekeeping action.

| Event/state | Required behavior |
|---|---|
| Waiting work in `bloke` or `ariza` | Retain task and current pointer; allow supervisor planning; deny worker claim/start |
| Room becomes `bloke` while task runs | Cancel with `oda_bloke`, retain cancelled pointer, set dirty |
| Ordinary block with no running work | Preserve cleanliness/current completed certification; block itself does not assert physical contamination |
| Room enters `ariza` | Invalidate readiness: dirty; cancel running task with `oda_ariza`; keep waiting task if any; otherwise clear completed/inspected pointer |
| Room becomes inactive | Cancel running task with `oda_pasif` and leave dirty; preserve other history; reject claim/start/complete/inspect |
| Block/fault released to `bos`, room dirty, module enabled | Keep existing waiting task; otherwise create one unassigned normal-priority `ekstra_temizlik` and set pointer |
| Block/fault released to `bos`, room clean | Do not create unnecessary work |
| Release while module disabled | Leave dirty backlog without producing a task |

A waiting task in a fault room remains dirty and current. If a previously cancelled task is replaced on release, use it as the predecessor only when it is still the current cancelled attempt. Release production never revives the cancelled row.

Implement separate internal room-lifecycle responsibilities: an always-on invalidator and an enabled-only dirty-room-release producer. The invalidator is necessary even when automatic creation is disabled. Room writes made by these functions must be recursion-safe: fire on actual usage/active transitions, not on their own pointer/cleanliness-only updates.

Returning `ariza` to `bos` grants access to clean, not readiness to check in. The room remains dirty until a successful task completes. A future Maintenance module owns work orders, technician assignments, parts and repairs; its release operation will use this same room contract.

## 11. Concurrency Model

### 11.1 Lock contract

**Decision:** Serialize cleanliness on the room row; use the existing core prefix for operations establishing a stay relationship.

**Reason:** A task lock alone cannot coordinate check-in, checkout, fault changes and task creation, especially when no task row exists yet.

**DB enforcement:** Ordered row locks plus immediate unique indexes and deferred final-state checks.

**Failure prevented:** Double claims, write skew, stale completion and task-first/room-first deadlocks.

New housekeeping operations acquire required locks in this order:

1. Relevant employee rows, sorted by ERP UUID. Lock the acting worker and any old/new assignee needed for the command with `FOR SHARE` when validating fields that can change. Re-read after locking. An initial task lookup used to discover candidate IDs is not authoritative.
2. Source reservation, if creating a stay-linked task: `FOR UPDATE`.
3. Source assignment, if creating a stay-linked task: `FOR UPDATE`.
4. Room: `FOR UPDATE`.
5. Current/predecessor/target task rows: `FOR UPDATE`, sorted by UUID if more than one.
6. The single `moduller` row for `pms_housekeeping`: `FOR SHARE`, followed by the final enabled-state decision.

The module lock is shared, so concurrent room operations do not serialize behind one another. Module enable/disable transactions must change the flag only; they MUST NOT also lock or mutate rooms/tasks. This gives disabling a drain barrier without a conflicting module-first business-write path.

Existing checkout already owns reservation/assignment/room locks; its trigger continues at task then module. It does not acquire new employee validation locks for assignment because its new task is unassigned. Creator FK checks retain their ordinary key locks. The user-scope guard never locks rooms, tasks or reservations, so those FK checks do not introduce a reverse business-lock path.

Existing-task claim/start/complete usually need only employee → room → task → module locks. They do not acquire reservation or assignment locks after the room. Unchanged source FKs must not be rewritten gratuitously. New stay-linked task insertion acquires its source prefix first; implicit FK locks are part of the lock analysis.

For a task command, read the immutable room ID for routing, authorize scope, lock the room, then re-read/lock the task and revalidate version, current pointer, actor and room state. The first unlocked lookup never authorizes mutation.

Task creation discovers a candidate current stay before locking; after locking the source prefix and room, it verifies the candidate is still the exact current assignment. If the candidate changed, fail with a state conflict. Do not acquire another source after the room lock.

Phase 1 reservation triggers also lock room types during their existing work. Housekeeping never takes room-type locks or rewrites reservation inventory. Tests must exercise the full trigger graph; this document does not claim all unrelated Phase 1 transactions are globally deadlock-free.

### 11.2 Race outcomes

| Race | Required serialized result |
|---|---|
| A. Two workers claim one task | One claims. Other receives version/ownership conflict; no claim stealing |
| B. Two creations for one room | First effective creation wins. Second conflicts unless it is the same creation receipt; active unique index is the structural backstop |
| C. Completion versus check-in | Completion first: room becomes clean, then check-in may succeed. Check-in first: it observes dirty/cleaning and fails; completion can then succeed |
| D. Checkout with unfinished task | Checkout cancels old attempt and creates fresh turnover work; old completion afterward is stale/terminal |
| E. Reassignment versus start | Reassignment first invalidates worker's version. Start first freezes assignee and rejects reassignment |
| F. Completion versus cancellation | Exactly one status transition succeeds. Loser cannot overwrite the winner or its room projection |
| G. Inspection versus check-in | Inspection first may certify then check-in proceeds. Check-in first retires pointer and inspection fails |
| H. Block/fault versus completion | Completion first may be followed by lifecycle invalidation. Lifecycle first cancels work and completion fails |
| I. Employee hotel-scope change versus assignment | Employee locking and the scope guard allow only a still-valid assignment/scope combination |
| J. Rework versus checkout/new stay | Current-pointer and usage rechecks prevent old rework from replacing a newer cycle |

Use default READ COMMITTED with these explicit locks. Do not depend on SERIALIZABLE to compensate for missing uniqueness. No exclusion constraint is needed: tasks are mutually exclusive current work, not overlapping scheduled intervals.

Use a 3-second transaction-local lock timeout for new interactive housekeeping commands and a 15-second statement budget. Do not silently overwrite Phase 1 checkout timeout behavior from a nested trigger. Keep all commands single-room; run batches as independent bounded requests.

Retry only transient deadlock, serialization or lock-timeout outcomes, with the same logical request, maximum three attempts with approximately 100/300/900ms backoff plus jitter. Refresh on business/version conflicts. Never blindly fetch a new version and retry an old user intention.

## 12. Idempotency

### 12.1 Creation receipts

**Decision:** Permanent creation deduplication plus a bounded last-command receipt on the task; no second ledger table.

**Reason:** Creation must not repeat even after completion. State commands need safe response-loss recovery, but need not return the original response indefinitely after later work.

**DB enforcement:** Creation-key uniqueness, immutable creation hash, `surum`, last-command key/hash, source uniqueness and predecessor uniqueness.

**Failure prevented:** Lost-response duplicate tasks, timestamp resets, old claims stealing later assignments, and changed payloads reusing an existing key.

Manual create/rework/handover creation requires a stable UUID request key generated before the first submission. The database computes the creation fingerprint from a canonical envelope containing operation name, actor ERP ID, actual hotel, room, type, expected usage, resolved source/predecessor, and normalized initial priority/deadline/notes. Include the predecessor's expected version for replacement operations. A same-key/different-envelope request is a conflict.

Canonicalization uses a fixed field set, explicit NULLs, trimmed validated text, numeric priority, UUID canonical text, and UTC-normalized timestamps. Unknown payload fields are rejected. SHA-256 is computed by PostgreSQL; a caller-provided hash is never trusted.

Read an existing creation receipt before applying current-room lifecycle preconditions. This permits a legitimate retry to return an already-created task even if it has since completed or lost its current pointer. Recheck caller permission and hotel scope before returning it; do not repoint the room or replay creation effects.

For manual tasks whose source is database-derived, resolve a found receipt against its stored immutable source rather than discovering a new stay on retry. A request's room/type/explicit predecessor and original normalized input must match. Existing creation fingerprints remain available even after notes/priority/deadline change.

Automatic checkout uses permanent source uniqueness; first insertion gets a random server key. Dirty-room release uses the actual room transition and the room lock; if waiting work exists, it does not create another row. A rolled-back transaction leaves neither a task nor a receipt.

### 12.2 Mutation receipts

Every mutation RPC takes task ID, `beklenen_surum`, a UUID `islem_anahtari`, and the action-specific payload. Its canonical hash includes operation, actor, actual hotel, task ID, expected version and normalized payload.

Under locks, after authentication/scope checks:

1. If the key equals `son_islem_anahtari` and the hash equals `son_islem_ozeti`, return the current task with `tekrar = true`; perform no DML, timestamp update, audit or projection change.
2. If the same last key has a different hash, return an idempotency conflict.
3. Otherwise require current version to equal `beklenen_surum`.
4. Validate the action's current-state/ownership/room preconditions.
5. On an actual change, increment version once and atomically save state, stamps, last key/hash and room effects.
6. For a metadata command already equal to the requested values at the expected version, return `degisiklik_yok`; do not change the receipt merely to log a no-op.

The retry guarantee is **no repeated effects**, with exact replay while the command remains the last effective command. After intervening work, the original expected version is stale and the request returns a conflict plus an authorized current snapshot. No automatic replay with a newer version is permitted.

Keys are not authentication. Even a recognized receipt requires current active-user, hotel and action-permission checks. The original command's state preconditions need not hold for a verified replay because the command already performed that transition.

### 12.3 API result contract

Successful write responses return task ID, room ID, hotel ID, task version/status/assignee, current room usage/cleanliness/pointer, and `tekrar` or `degisiklik_yok` flags. Replacement commands return predecessor and successor IDs. The same request key must survive a network timeout on the client.

Use PostgreSQL permission code `42501` for authorization failure, a not-found-or-inaccessible outcome that does not disclose another hotel's record, and stable application detail codes for `HK_SURUM_CAKISMASI`, `HK_DURUM_CAKISMASI`, `HK_AKTIF_GOREV_VAR`, `HK_ISTEK_CAKISMASI`, `HK_ODA_KULLANILAMAZ`, and `HK_MODUL_KAPALI`. Map business conflicts to an HTTP conflict response at the RPC boundary; preserve unexpected database errors rather than labelling them success.

### 12.4 Internal command receipts

**Decision:** Internal and automatic operations generate their own command key and fingerprint server-side. `son_islem_anahtari` and `son_islem_ozeti` stay NOT NULL for every path.

**Reason:** The receipt columns exist so that a mutation can prove which command last changed the row. Producers, the room lifecycle invalidator and any other sealed internal mutation have no client key, but they still mutate rows, so they must still leave a receipt.

**DB enforcement:** NOT NULL receipt columns, server-side `gen_random_uuid()`, server-computed SHA-256 over the canonical internal envelope, and the same one-transaction rule as user commands.

**Failure prevented:** Unsatisfiable NOT NULL on producer paths, and a caller-supplied "internal" key being accepted as trusted evidence.

For an internal mutation with no client-supplied command key:

1. Generate the key with `gen_random_uuid()` **inside the database**, after locking.
2. Compute the fingerprint server-side over the canonical internal envelope: internal action code, creation origin, actual hotel, room, task, expected/observed version and the normalized internal payload, including the controlled cancellation reason where applicable.
3. Never accept a caller-supplied internal actor, key or hash as trusted evidence. A REST caller cannot select an internal action, an internal key namespace or `olusturma_kaynagi`.
4. Task mutation, receipt update, room projection and audit remain in one transaction.

Internal receipts are **write-only evidence**, not a replay contract: an internal operation is never re-submitted by a client, so no lookup path compares an incoming key to an internally generated one. Idempotency for automatic work continues to come from its structural sources — the checkout source unique index, the unfinished-task unique index, the predecessor unique index and the room lock — exactly as in sections 8.3 and 12.1. Nothing here weakens the user-facing contract.

For user-facing RPCs the existing client-stable request/command key contract in 12.1 and 12.2 is unchanged: the client generates a stable UUID once per intention and reuses it across network retries.

Section 8.2 step 6 says the producer must not overwrite the invalidator's receipt or stamps. Concretely: the invalidator's cancellation wrote its own internal receipt when it cancelled the superseded task, and the producer reads that row without rewriting it.

## 13. Direct REST / DML Protection

### 13.1 Column ownership

| Class | Columns | Access contract |
|---|---|---|
| A. Direct REST editable | None on tasks | Even notes use an RPC, preserving lock order and versions |
| B. Creation-only immutable | IDs, hotel, room, type, creation origin, source, predecessor, creator, creation time/key/hash | Insert guard sets/validates; update guard freezes |
| C. Command-only | Status, assignee, notes, priority, deadline, cancellation reason, inspector | Purpose-specific RPC and allowlisted deltas |
| D. System-maintained | Event/update timestamps, version, last receipt, room pointer and cleanliness projection | Database sets; caller cannot supply overrides |

**Decision:** Authenticated task access is SELECT-only. Task commands are narrowly scoped SECURITY DEFINER functions.

**Reason:** Keeping invoker task writes would require table DML grants, including single-table state changes that a direct REST client could also attempt. Workers must not receive general room-management write access.

**DB enforcement:** Explicit task DML revocation; no write RLS policies; sealed RPC ACLs; BEFORE mutation guards; FKs/CHECKs/uniques; final consistency triggers.

**Failure prevented:** Direct PATCH bypass, forged ownership/stamps, upsert-created completed tasks and unauthorized room readiness changes.

### 13.2 Command surface

These are API contracts, not implementation bodies:

| RPC | Action-specific input | Minimum permission |
|---|---|---|
| `pms_housekeeping_gorev_olustur` | Room, expected usage, allowed manual type, initial priority/deadline/notes, creation key | `tam` |
| `pms_housekeeping_sahiplen` | Task, expected version, command key | `kayit`, self only |
| `pms_housekeeping_birak` | Task, expected version, command key | `kayit`, own waiting task |
| `pms_housekeeping_ata` | Task, target ERP user or NULL, expected version, command key | `tam`, waiting only |
| `pms_housekeeping_baslat` | Task, expected version, command key | `kayit`, assignee only |
| `pms_housekeeping_tamamla` | Task, expected version, command key | `kayit`, assignee only |
| `pms_housekeeping_kontrol_et` | Task, expected version, command key | `tam`, different inspector |
| `pms_housekeeping_iptal` | Task, required explanation, expected version, command key | `tam` |
| `pms_housekeeping_duzenle` | Task, permitted note/priority/deadline changes, expected version, command key | Own unfinished notes: `kayit`; any unfinished notes or waiting planning metadata: `tam` |
| `pms_housekeeping_yeniden_ac` | Current completed/inspected predecessor, expected version, explanation, creation key | `tam`, vacant room |
| `pms_housekeeping_devret` | Current running predecessor, expected version, explanation, creation key | `tam`; atomic cancel + unassigned successor |

The public manual-create RPC cannot choose `cikis_temizligi`, source assignment, creator, initial assignee, initial state or event stamps. A supervisor assigns a created task with the normal assignment RPC. A general-purpose state setter is forbidden.

All wrapper mutations call one private transition/projection implementation to avoid duplicated state/room logic. Private helpers live in the already-private schema where suitable, retain explicit ACLs, and are callable only by the trusted function owner. They accept only enumerated internal actions, not arbitrary table names or SQL.

### 13.3 Guard responsibilities

- `pms_housekeeping_gorev_koruma`: BEFORE INSERT/UPDATE/DELETE; valid initial state, transition matrix, immutable fields, stamps, exact version increments and terminal freeze; operational DELETE always denied.
- `pms_housekeeping_oda_koruma`: BEFORE room INSERT/UPDATE; protect cleanliness and pointer writes while allowing exact Phase 1 lifecycle transitions.
- `pms_housekeeping_tutarlilik_gorev` and `pms_housekeeping_tutarlilik_oda`: deferred constraint triggers checking H1–H10 from final rows.
- Room lifecycle invalidator: react only to real room usage/active changes, with sealed cancellation/readiness invalidation.
- Employee-scope guard: prevents active assignments from crossing a user's reduced hotel scope.

#### 13.3.1 Required BEFORE trigger order on `pms_odalar`

PostgreSQL fires row-level BEFORE triggers **in alphabetical order of trigger name**, using the database collation. The Phase 2 trigger name is therefore a correctness decision, not a label. It MUST be documented and asserted, never left to accident.

The chosen name is order-stable across collations: whether or not the collation ignores underscores at the primary level, `pms_h…` sorts before `pms_o…`. The catalog test below is nevertheless the authority, because it sorts exactly the way the executor does.

Current triggers on `public.pms_odalar`, in firing order:

| # | Trigger | Timing | Responsibility |
|---|---|---|---|
| 1 | `phase0_otel_degismez` | BEFORE UPDATE OF `otel_id` | Rejects any hotel change |
| 2 | `pms_oda_envanter_kontrol` | BEFORE DELETE OR UPDATE | Room-type inventory floor; returns early when `aktif`/`oda_tipi_id`/`otel_id` are unchanged |
| 3 | `pms_oda_gecis` | BEFORE INSERT OR UPDATE | Phase 1 usage/cleanliness transition rules |
| 4 | `pms_odalar_guncelleme` | BEFORE UPDATE | Stamps `guncelleme_tarihi` |

**Required name and position:** `pms_housekeeping_oda_koruma`, firing at **position 2**, immediately after `phase0_otel_degismez` and **before** `pms_oda_envanter_kontrol` and `pms_oda_gecis`.

| # | Trigger | Sees |
|---|---|---|
| 1 | `phase0_otel_degismez` | Raw OLD/NEW; hotel immutability first, so every later guard can trust `otel_id` |
| 2 | **`pms_housekeeping_oda_koruma`** | **Raw client-supplied NEW.** This is the point of the position: it must judge the caller's *actual* submitted cleanliness and pointer before any other guard has evaluated or accepted them |
| 3 | `pms_oda_envanter_kontrol` | A NEW whose cleanliness/pointer are already authorized |
| 4 | `pms_oda_gecis` | Same; its `dolu`-transition cleanliness check now runs on a value housekeeping has already confirmed is unspoofed |
| 5 | `pms_odalar_guncelleme` | Final NEW; stamps last, so the stamp reflects the committed shape |

**Reason for this position, not a later one:** `pms_oda_gecis` validates `NEW.temizlik_durumu` on the `bos → dolu` transition. `NEW` is client-supplied, so a caller can present `temiz` on a physically dirty room and Phase 1 alone would accept it. The housekeeping guard closes that by requiring the **OLD locked** value to be `temiz`/`kontrol_edildi` and the incoming value to be unchanged. Running it before `pms_oda_gecis` means the spoofed value never reaches the Phase 1 check at all; running it later would leave a window in which a second guard had already approved a forged field.

No existing BEFORE trigger on this table mutates `NEW` — `phase0_otel_degismez`, `pms_oda_envanter_kontrol` and `pms_oda_gecis` only raise, and `pms_odalar_guncelleme` fires last. Housekeeping therefore sees exactly what the client sent, and nothing it approves is later rewritten.

**Required catalog test** (section 22.2 case 38): assert by query, not by inspection, that `pms_odalar` has exactly these five BEFORE row triggers, that their `tgname` ordering places `pms_housekeeping_oda_koruma` second, and that renaming it would fail the assertion. Order the catalog query the way PostgreSQL does:

```sql
select tgname from pg_trigger
 where tgrelid = 'public.pms_odalar'::regclass
   and not tgisinternal and (tgtype & 2) <> 0   -- BEFORE
 order by tgname;
```

For application clients, allow new room INSERT only with NULL task pointer and `kirli` cleanliness after Phase 2 activation. Room creation cannot bootstrap a clean/inspected room outside housekeeping. Existing migrated clean rooms remain grandfathered as described in section 7.

### 13.4 Existing room DML and trusted execution

#### 13.4.1 Measured `pms_odalar` privileges — least privilege table

The existing grant is **not** merely UPDATE. The schema dump records:

```sql
GRANT ALL ON TABLE public.pms_odalar TO authenticated;
```

`authenticated` therefore holds every table privilege, including TRUNCATE, REFERENCES and TRIGGER. The cause is the Phase 1 Step 1 migration revoking only `from public, anon` before granting, so the default-ACL `ALL` for `authenticated` survived. This is the observable consequence of the checker's `R2-REVOKE-EKSIK-ROL` finding on that file.

**Consequences to state plainly:**

- The row guards in this section protect **row-level DML paths** — INSERT, UPDATE, DELETE.
- **TRUNCATE does not fire row triggers.** A TRUNCATE would bypass `pms_housekeeping_oda_koruma`, `pms_oda_gecis` and `pms_oda_envanter_kontrol` alike.
- PostgREST does not expose TRUNCATE, REFERENCES or TRIGGER, so **this is not currently an application exploit path**. It is excess privilege, not an open door.
- Phase 2 may tighten it forward, but MUST NOT edit the Phase 1 migration.

| Privilege | Granted now | Used now | Evidence | Recommendation |
|---|---|---|---|---|
| SELECT | yes | **yes** | `pms-oda-plani.html`, `pms-odalar.html`, `pms-rezervasyonlar.html` bulk reads | **Retain** |
| INSERT | yes | **yes** | `pms-odalar.html` room creation (`method:'POST'`) | **Retain** |
| UPDATE | yes | **yes** | `pms-odalar.html` room edit; `pms-oda-plani.html` cleanliness PATCH; invoker `pms_check_in` / `pms_check_out` | **Retain** — required by Phase 1 |
| DELETE | yes | **no** | No `DELETE` against `pms_odalar` anywhere in the frontend; retirement uses the `aktif` flag; `pms_oda_atamalari` FK is `ON DELETE RESTRICT` | **Revoke (optional, reversible)** — behaviour change with no known caller; confirm no administrative flow depends on it before doing so |
| TRUNCATE | yes | **no** | Not reachable through PostgREST; no caller | **Revoke** |
| REFERENCES | yes | **no** | Only needed to create FKs referencing this table; migrations run as `postgres` | **Revoke** |
| TRIGGER | yes | **no** | Only needed to create triggers on this table; migrations run as `postgres` | **Revoke** |

Recommended Phase 2 forward tightening, in the new migration only:

```sql
revoke truncate, references, trigger on table public.pms_odalar from authenticated;
-- Optional, after confirming no administrative caller:
-- revoke delete on table public.pms_odalar from authenticated;
```

This is a **new forward migration statement**, not an edit to Phase 1. It cannot break check-in, check-out, the Room Rack or room management, because none of those use the revoked privileges. Verify with a REST test as the real `authenticated` role before and after (section 22.2 case 39), and do not revoke anything this table does not prove is unused.

Do not revoke the room UPDATE privilege needed by the existing invoker check-in/out. A column-level revoke does not override an existing table-level UPDATE grant.

Keep the room guard SECURITY INVOKER so it can distinguish an application-role statement from a trusted definer statement using `current_user`. The trusted writer is the existing approved `postgres` function owner, not `authenticated` or `service_role`. Application users must have no membership allowing them to assume that role. PostgreSQL administrators remain the explicit administrative trust boundary.

The invoker guard's application-role branch uses OLD/NEW room fields and public auth helpers; it must not depend on reading housekeeping rows hidden from reception by RLS. Cross-table checks run in separately sealed definer constraint functions. This avoids requiring broad housekeeping privileges for ordinary checkout.

For raw application room writes:

- Deny caller-changed task pointer.
- Deny cleanliness changes except the exact existing occupied → vacant dirtying transition, with existing reservation permission/scope and Phase 1 consistency checks.
- On check-in, verify old locked clean readiness and unchanged incoming cleanliness, then internally clear the pointer.
- Preserve permitted room metadata/availability management; lifecycle triggers maintain housekeeping consequences.

For trusted housekeeping projection writes, still enforce all transition/CHECK/FK/final consistency rules. A privileged execution context is not a licence to commit inconsistent data.

Do not use a client-settable GUC, request header, supplied actor ID, temporary flag or `pg_trigger_depth()` as proof of authorization. The existing user-visible REST table grants never permit setting such a trusted context.

## 14. Multi-Hotel Integrity

### 14.1 Actor and business references

Every task has non-NULL enum `otel_id`. Room, source assignment and predecessor use composite references including hotel and room, so cross-hotel and wrong-room references fail independently of RLS.

Authenticate through `auth.uid()` and resolve the ERP ID through the existing user mapping. Verify `auth_erp_kullanicisi() IS TRUE`, the command's `auth_yetki_var(...) IS TRUE`, and `auth_otel_erisim(actual_row.otel_id::text) IS TRUE`. Do not trust hotel selection or role information stored in browser session data.

### 14.2 Employee assignment

**Decision:** Use an ordinary ERP user FK plus a DB eligibility guard, not a false employee `(id, home_hotel)` composite FK.

**Reason:** `tum_oteller = true` grants legitimate multi-hotel access; a home-hotel FK would reject those employees. Creating a new membership table would create a second authority.

**DB enforcement:** Lock and query the existing employee/role/matrix/module records; require an active Auth-linked employee, current hotel access, and housekeeping `kayit`/`tam`.

**Failure prevented:** Foreign-hotel assignment, assignment to an inactive/non-ERP person, and inconsistent parallel authorization.

An assignable employee must satisfy all of:

1. The ERP user exists and `aktif IS TRUE`.
2. `auth_user_id` is populated.
3. `tum_oteller IS TRUE` or `otel_id` equals the task hotel.
4. The employee's `rol_id` has `kayit` or `tam` for the active housekeeping module in the existing permission matrix.

Implement one private target-user eligibility helper over these existing tables. Existing `auth_*` helpers evaluate the caller; do not impersonate the target or mutate JWT claims to reuse them. The helper is an adapter to the same authority, not a separate permission system.

### 14.3 Scope changes and deactivation

On changes to employee `otel_id`/`tum_oteller`, a definer BEFORE guard rejects any resulting scope that excludes the hotel of that employee's unfinished assignments. The scope change holds the employee row's write lock; assignment holds `FOR SHARE` before room/task locks. The guard reads tasks without taking reverse room/task locks. Thus either a new assignment sees the new scope and fails, or a scope reduction sees the committed assignment and fails.

Deactivation and permission revocation are never blocked merely to keep a task executable. Retain the historical assignee value but reject that person's subsequent commands and flag their unfinished tasks as requiring supervisor reassignment/cancellation. Assignment eligibility is a current authorization check, not an assertion that a historical UUID grants continuing rights.

Revalidate actor/target eligibility after waits. Role revocation takes effect for subsequent authorized commands; this does not retroactively undo an already authorized, serialized transaction. User deletion is restricted by history references; deactivate users instead. Removing an Auth link denies future execution without erasing ERP attribution.

## 15. RLS Design

Enable RLS explicitly on `pms_housekeeping_gorevleri`.

| Policy | Mode/operation | Predicate |
|---|---|---|
| `pms_housekeeping_gorevleri_select` | Permissive SELECT to authenticated | Active ERP caller, housekeeping `goruntule`, actual hotel access, all fail-closed |
| `phase0_otel_kisit` | Restrictive ALL to authenticated | Active ERP caller and hotel access in both USING and WITH CHECK |

No authenticated INSERT/UPDATE/DELETE policy is installed because task DML is not granted. Operation-specific means policies for operations actually exposed, not four permissive policies added for symmetry.

Restricted reads use these RPC contracts:

- `pms_housekeeping_listele`: required hotel; queue/date/floor/room/worker/priority filters; bounded cursor page; sanitized task and room projection.
- `pms_housekeeping_calisanlar`: required hotel; eligible ERP IDs and display names only; caller must have housekeeping visibility.
- `pms_housekeeping_oda_ozet`: required hotel and at most 500 room IDs; current task summary only for accessible rooms; used by Room Rack.

These narrow definer reads require housekeeping `goruntule`, active ERP identity and explicit hotel filtering in every base relation. They avoid granting workers room management, reservation, guest or user-management permissions. Task notes are operationally visible within the authorized hotel; no guest data is added to these projections.

Reception receives housekeeping `goruntule` to see task details. Without that grant, existing room-read permission still exposes the ordinary room readiness flags, not housekeeping notes/assignees. Do not add a broad room/user SELECT policy to solve a join problem.

`anon` has no table or RPC access. A missing module permission or NULL auth result denies access. Module `aktif = false` closes authenticated task reads and public housekeeping commands. Internal lifecycle invalidation remains a separate sealed responsibility.

If a view is introduced in future, it must have `security_invoker = true` and explicit minimal ACLs. No definer view is needed for this design. RLS is not assumed to constrain the privileged owner or platform BYPASSRLS roles; RPC bodies and guards remain required.

## 16. Permission Model

Register **`pms_housekeeping`** in the existing module system. Use only `yok`, `goruntule`, `kayit`, `tam`.

### 16.1 Exact module record

`public.moduller` requires five columns. `kategori` is NOT NULL with **no default**; omitting it aborts the migration with `23502`. `aktif` defaults to `true`, so an inactive install must set it explicitly.

```sql
insert into public.moduller (kod, ad, kategori, sira, aktif) values
  ('pms_housekeeping', 'Kat Hizmetleri', 'onburo', 49, false)
on conflict (kod) do nothing;
```

| Column | Value | Source |
|---|---|---|
| `kod` | `pms_housekeeping` | This document |
| `ad` | `Kat Hizmetleri` | This document |
| `kategori` | `onburo` | Existing PMS convention: all six Phase 1 PMS modules use `onburo` |
| `sira` | `49` | Highest current `onburo` value is `48` (`pms_folio`); `49` is also globally unused — next used value is `60` (`ai_analiz_merkezi`). Measured from repository reference data, not chosen arbitrarily |
| `aktif` | `false` | Installed inactive; see below |

The Phase 1 module labels use the `Ön Büro — X` prefix. Housekeeping is deliberately **not** a front-office screen — its primary users are cleaning staff — so it keeps the plain label `Kat Hizmetleri` while staying in the `onburo` category for menu placement. Record this as an intentional deviation, not an oversight.

Before writing the migration, re-measure rather than trusting this number if other modules were added meanwhile:

```sql
select kategori, max(sira) from public.moduller
 where kategori = 'onburo' group by kategori;
```

| Level | Rights |
|---|---|
| `yok` | No task data or housekeeping commands |
| `goruntule` | Read permitted-hotel queues, status, assignee, operational notes and readiness |
| `kayit` | Read; claim; release own waiting claim; start/complete own task; edit own unfinished notes |
| `tam` | All prior rights; create; assign/reassign/unassign waiting work; edit waiting priority/deadline; inspect; cancel; rework; controlled running handover |

`tam` does not grant historical edits, invalid transitions, cross-hotel actions or completion under another employee's identity. Inspector identity is derived from the caller and must differ from the cleaner.

Workers receive housekeeping `kayit`; supervisors receive `tam`; reception receives `goruntule`. Do not infer these from free-text department labels or hardcoded legacy role names.

The new module is installed inactive (`aktif = false`, see 16.1) with no automatic role grants. Explicitly configure the selected roles through the existing permission mechanism, deploy compatible UI, and then enable. No missing matrix row means implied access.

Because `auth_yetki_var()` requires `m.aktif is true`, an inactive module closes every housekeeping read and public command by construction — the same mechanism section 24.1 relies on for disable.

Checkout requires its existing reservation permission, not housekeeping write permission. Automatic cancellation/task production is a verified side effect of that authorized business event. Room availability transitions require their existing room permissions; workers cannot unblock rooms.

## 17. Migration Security Requirements

### 17.1 New forward migration only

The future implementation belongs in `docs/kurulum/<date>-pms-faz2-adim1-housekeeping.sql`. Do not edit the four Phase 1 migrations, their SHA manifests, or historical applied SQL. Use explicit prerequisites and one atomic migration transaction; abort on an incompatible pre-existing object instead of assuming `IF NOT EXISTS` proves the desired definition.

Prerequisites include the exact room/assignment keys and types, auth helpers, audit table/writer, private schema, Phase 1 transition/consistency triggers, and zero unadopted legacy running-cleanliness rooms. Missing audit or immutability infrastructure is a hard error, not a NOTICE-and-skip path.

### 17.2 ACL contract

For the new task TABLE:

1. Revoke ALL from PUBLIC.
2. Revoke ALL from anon.
3. Revoke ALL from authenticated.
4. Neutralize inherited service-role privileges as well.
5. Grant authenticated SELECT only.
6. Grant service_role no task DML or public task-command execution in Step 1; no service-role task API is required.
7. Enable RLS and install the two defined policies.

No new sequence is required. If a later approved change adds one, explicitly revoke PUBLIC/anon/authenticated defaults and grant only actual required USAGE, never authenticated ALL or setval rights.

For every new/replaced FUNCTION, explicitly revoke PUBLIC/anon EXECUTE. Also revoke inherited authenticated/service-role EXECUTE before granting the intended callable surface. Grant public command/read RPC execution to authenticated only. Private helpers and trigger functions receive no application-role execution grants; PostgreSQL invokes installed triggers without needing a new public RPC surface.

Perform a final ACL sweep over exact Phase 2 function identities, including trigger functions and private helpers. Do not sweep unrelated historical functions. Existing triggers must retain a valid owner and creation-time execution privilege.

### 17.3 Definer justifications and scope

| Function class | Security choice | Justification |
|---|---|---|
| Public task command | DEFINER | Clients intentionally lack task DML and worker room-write rights |
| Restricted list/employee/room-summary read | DEFINER | Return a limited projection without broad user/guest/room grants |
| Checkout/release producer and lifecycle invalidator | DEFINER | Authorized source event needs narrow task side effects |
| Cross-table consistency checker / employee scope guard | DEFINER | Hidden rows must not be mistaken for absent rows |
| Generic transactional audit writer | Existing DEFINER | Audit insertion is not a client privilege |
| Room route guard | INVOKER | Must distinguish raw application writes from trusted nested writes |
| Pure row shape/transition guard | INVOKER where sufficient | No extra authority needed to inspect OLD/NEW and reject invalid deltas |

Pin search_path to `pg_catalog` with qualified names, or the approved `pg_catalog, public, pg_temp` pattern with all security-sensitive references qualified. Every definer validates auth and actual hotel scope at its public boundary. No caller-controlled dynamic SQL, no arbitrary actor parameter and no service-role auth exemption in public housekeeping commands.

Use the existing approved trusted function owner; do not create a new database role/schema or change platform roles as part of this feature. That owner's broad administrative power is an explicit trust boundary. Least privilege is enforced through the exposed capabilities and application ACLs, not by claiming owner RLS applies.

### 17.4 Checker and baseline requirements

Follow [[MIGRATION-GUVENLIK-STANDARDI]] and `SABLON-yeni-migration.sql`. The future migration must pass the target-file invocation of `node scripts/migration-guvenlik-kontrol.mjs` with `--uyari-da-hata`, and the existing `node --test scripts/migration-guvenlik-kontrol.test.mjs` suite.

The checker does not validate all policy predicates, FK columns, trigger bodies, implicit locks or private-schema objects equally. Add catalog assertions and behavioral tests for those contracts. Do not weaken the checker or add broad `@acl-istisna` exemptions to make this design pass. Tasks are controlled-mutable, not `@append-only` tables.

### 17.5 Expected baseline delta

Phase 2 changes counters that existing release gates assert. They are listed here so a red gate is recognised as expected, not as drift. **Deterministic** rows are fixed by this architecture. **Implementation-dependent** rows must be measured from the candidate migration before release; they are not hardcoded here.

| Counter | Asserted by | Current | Phase 2 | Basis |
|---|---|---|---|---|
| Public table count | fingerprint, equality | 75 | **76** | Deterministic: one new task table |
| Policy count | fingerprint, equality | 234 | **236** | Deterministic: one SELECT policy plus one restrictive policy |
| Restrictive policy count | fingerprint, equality | 40 | **41** | Deterministic: one `phase0_otel_kisit` on the task table |
| `phase0_otel_degismez` trigger count | equality check | 34 | **35** | Deterministic: the task table is updateable and adopts the shared convention (section 4.4) |
| `phase0_islem_audit` trigger count | equality check | 19 | at least **20** | Task table audit trigger is deterministic. Whether the room audit trigger reuses this exact name is an implementation choice; if it does, the value is **21**. Measure from candidate migration before release |
| Public SECURITY DEFINER / `auth_*` function fingerprint scope | equality check | 28 | grows | Implementation-dependent: the exact public RPC, producer and guard count is not frozen. **Measure from candidate migration before release; do not hardcode until implementation is frozen** |
| `pms_odalar` column count | schema dump | — | +1 | Deterministic: `temizlik_gorevi_id` |
| `erp_islem_audit` column count | schema dump | — | +1 | Deterministic: nullable `islem_detayi jsonb`; this is a column, not a new table |

Two facts that prevent false alarms:

- The equality validator's function-body hash scope is `n.nspname = 'public'` only. `phase0_private.islem_audit()` is in `phase0_private`, so replacing it to add opt-in detail capture does **not** move any pinned function hash. Its change is still recorded explicitly (section 18).
- Housekeeping adds no sequence and changes no Realtime publication membership, so those counters stay flat.

Produce the new post-Phase-2 fingerprint and equality artifacts from the completed migration, keep the Phase 1 baselines intact, and record every intentional counter change with its reason. Verify actual migration deltas instead of copying counts blindly.

Retain zero RLS-disabled tables, zero unpinned definers and zero anonymous table/sequence/PMS-function exposure. Produce a new post-Phase-2 fingerprint/equality artifact in the later implementation workflow. Keep historical baselines intact. Record approved shared-audit function changes explicitly.

Platform default ACL, ensure_rls recreation and BYPASSRLS risks remain the existing monitored platform concerns; this feature neither repairs nor relies on bypassing them. Realtime publication membership remains unchanged.

## 18. Audit Design

**Decision:** Reuse `erp_islem_audit` and extend its existing writer with an opt-in housekeeping detail mode. Do not create a housekeeping audit table or client audit request.

**Reason:** Existing rows prove CRUD/actor/entity/transaction, but cannot distinguish reassignment from completion or retain the previous assignee. Full-row snapshots would copy unnecessary PII and notes.

**DB enforcement:** Add nullable `islem_detayi jsonb`; extend `phase0_private.islem_audit()` for an explicit housekeeping trigger argument; attach one authoritative audit trigger per effective task event and relevant room event.

**Failure prevented:** Missing semantic history, duplicate audit systems, unaudited room readiness and business commits without their audit evidence.

Keep existing audit `event_type` values exactly INSERT/UPDATE/DELETE. The semantic action is an allowlisted value within `islem_detayi`. Existing callers without the housekeeping argument produce the same legacy record shape with NULL detail. Existing rows need no backfill.

The detail object contains only the applicable subset of: action code, old/new task status, old/new assignee ERP UUID, old/new task version, room UUID, source assignment/predecessor UUID, old/new cleanliness, old/new pointer, command UUID, controlled cancellation reason, and changed-field names. Omit note bodies, guest data, employee names, request payloads, credentials and full OLD/NEW JSON snapshots.

| Event | Required transactional evidence |
|---|---|
| Create | Task INSERT with type/source/predecessor context |
| Assign/reassign/unassign | Old/new assignee and versions |
| Self-claim/release | Actor-derived self-assignment/release classification |
| Start | Waiting → running with task start stamp and actor |
| Complete | Running → completed with completion stamp and actor |
| Inspect | Completed → inspected and inspector |
| Cancel | Prior state → cancelled, controlled reason |
| Note/priority/deadline edit | Changed-field names and version; no note contents |
| Room readiness/pointer transition | Relevant old/new cleanliness and cycle identity |
| Checkout supersession | Old cancellation, new creation and room effects sharing checkout transaction ID |

For assignment, classify self-claim when an unassigned task becomes assigned to the actor; supervisor self-assignment has the same observable meaning. For replacement/rework, the new task's predecessor and old task cancellation, if any, establish the action. Do not obtain the event type from a client-settable session flag.

Filter out room metadata-only updates. Room check-in pointer retirement is a lifecycle audit event even if cleanliness is unchanged. A no-op/replay does not fire a business update or produce another audit row.

The existing writer still derives actor from authenticated database context and stores `pg_current_xact_id()` transaction identity. An automatic task's `olusturan` is the actual reception or room-operation actor when one is resolvable, and NULL otherwise — never a fabricated housekeeping worker (4.1.1). The audit row remains the authority for the database actor even when the task row carries none, because `erp_islem_audit.actor_role` already accepts `service_role` with a NULL `actor_user_id`. Include `olusturma_kaynagi` in the creation detail object so the origin is auditable. Audit insertion failure rolls back the task, room and source checkout transaction.

Audit ACLs, restrictive boundary and immutability guard remain in place. Housekeeping visibility does not grant broad `denetim_izi` access. Operational task screens use task fields; administrative event history continues to use the existing audit permission. Test legacy audit behavior explicitly because the opt-in writer change is a shared dependency.

## 19. UI Architecture

Create `pms-housekeeping.html` with the existing login/auth header, hotel naming, theme, shared notifications and permission-filtered navigation conventions. Use a small shared `pms-housekeeping.js` RPC adapter with Room Rack; it centralizes request identities, version submission and HTTP error handling, not database state-machine authority.

### Phone workflow

- Sticky hotel selector and floor filter. Even all-hotel users select one hotel per operational queue.
- Primary tabs: **İşlerim**, **Bekleyen**, **Kontrol**, **Tümü**.
- Visible room search; secondary filter sheet for room, status, worker, type and priority.
- One-column cards with large room number, floor/block, separate occupancy and cleanliness labels, task type, assignee and priority.
- Display waiting/running age; show an overdue badge only when an unfinished task has a real `hedef_zamani` earlier than server time.
- Show one primary eligible action: Claim, Start, Complete or Inspect.
- Put assignment, reassignment, note editing, cancellation, handover and rework in a bottom sheet.
- At least approximately 44px touch targets, explicit action labels and adequate contrast; do not communicate status through color alone.

Worker default view is own unfinished work, with unassigned work reachable in one tap. Supervisors see hotel workload and exception counts. Reception uses read-only visibility. No guest identity or folio data appears on housekeeping cards.

Show separate operational exceptions: `Kirli — görev yok`, unavailable assigned employee, blocked/fault waiting work and stale-data state. A blocked card explains why its work action is unavailable. A missing permission is not presented as an empty hotel without explanation.

### Request/response behavior

- Generate a creation/command UUID once per user intention, retaining it across network retry. Keep only the minimal pending-command envelope in session storage; clear it on logout or confirmed resolution. It is not an offline work queue.
- Disable only the affected action while pending. Do not optimistically show a completed or inspected room before server acknowledgement.
- Check `response.ok` explicitly. Existing `ortak.js` `sbYaz()` returns HTTP failures without throwing; awaiting it alone is not success.
- Surface stable business errors and refreshed authoritative version/state. A conflict does not silently retry against a newer version.
- On lost response, submit the same receipt or reconcile current state. Never create another request key solely because a timeout occurred.
- Use the combined room/task command response to refresh the affected card; refresh the queue afterward.
- Refresh on page focus and every 30 seconds while visible. Pause polling when hidden; retain manual refresh.
- Do not add offline completion, automatic background mutations, decorative analytics, geolocation or push notifications in Step 1.

The page must contain the DOM elements required by shared loader/toast helpers and escape operational notes. Prefer safe DOM text insertion. If existing inline-event conventions are reused, apply the existing JavaScript-plus-HTML escaping helper correctly.

## 20. Room Rack Integration

**Decision:** Room Rack displays the same current-cycle contract and calls the same housekeeping command adapter.

**Reason:** The current Rack's direct cleanliness PATCH and local next-state map would otherwise remain a competing transition path.

**DB enforcement:** The room guard rejects legacy direct cleanliness transitions. Rack submits the task ID/version or opens the housekeeping task detail; PostgreSQL rechecks readiness.

**Failure prevented:** Two different cleaning workflows and a stale Rack button overriding a newer task.

Required future changes in `pms-oda-plani.html`:

1. Replace `TEMIZLIK_SONRAKI` and `temizlikDegistir()` direct PATCH behavior with task-aware commands/deep links.
2. Keep occupancy and cleanliness visually distinct.
3. Add a current task badge, assignee, urgency and a housekeeping deep link when authorized.
4. Show dirty-without-task explicitly. Task creation is a supervisor action, not an automatic consequence of viewing a card.
5. Preserve the existing clean/inspected check-in display; server checks remain decisive.
6. Read task summaries in one bounded request for visible hotel rooms; never issue a request per card.
7. Use an ID-to-record map for joins instead of repeated nested `.find()` calls over growing histories.
8. Correct the touched `doluRez()` occupancy lookup: active assignment plus `giris_yapildi` reservation, without a planned-departure-date gate. Expired planned departures remain physically occupied.
9. Confirm write response success before toasts or UI completion. Existing nonthrowing HTTP helper behavior must not produce false success.

A combined summary returns task and room readiness from one database statement snapshot. If the Rack's existing bulk data and the summary arrive from different snapshots, render actionable housekeeping controls from the summary's room/task pair and refresh on conflict. Do not infer database drift solely from two HTTP reads taken at different times.

Add a permission-filtered direct housekeeping navigation entry in `nav-drawer.js`. Workers must be able to reach it without guest or reservation-module access. Do not broaden their role solely to make the existing front-office hub visible.

## 21. Performance / Index Strategy

### 21.1 Required initial indexes

Create these indexes with the task table; the empty-table migration does not need concurrent index creation. Validate actual definitions, uniqueness and predicates, not names alone.

| Index/key | Ordered columns and predicate | Purpose |
|---|---|---|
| Task PK | `id` | Command lookup |
| Task composite unique key | `id, oda_id, otel_id` | Same-room/hotel pointer and predecessor FKs |
| `pms_housekeeping_aktif_oda_uniq` | Unique `otel_id, oda_id`; only `bekliyor`/`temizleniyor` | One unfinished task and hotel working set |
| `pms_housekeeping_istek_uniq` | Unique `otel_id, istek_anahtari`; all history | Permanent creation receipt |
| `pms_housekeeping_cikis_kaynak_uniq` | Unique `otel_id, kaynak_atama_id`; only `cikis_temizligi` | One task per actual checkout source |
| `pms_housekeeping_onceki_uniq` | Unique `otel_id, onceki_gorev_id`; predecessor not NULL | One successor per predecessor |
| `pms_housekeeping_otel_tarih_idx` | `otel_id, olusturma_tarihi DESC, id DESC` | Today's/history task pages |
| `pms_housekeeping_oda_tarih_idx` | `otel_id, oda_id, olusturma_tarihi DESC, id DESC` | Room history and room FK maintenance |
| `pms_housekeeping_calisan_aktif_idx` | `otel_id, atanan_kullanici_id, olusturma_tarihi, id`; unfinished only | Worker queue |
| `pms_housekeeping_kaynak_atama_idx` | `kaynak_atama_id, oda_id, otel_id`; source not NULL | Source FK checks across all task types |

Also add the assignment composite target unique key specified in section 4. No new standalone index is needed merely for task `durum`; active queues are bounded by room count. Do not add a time-dependent partial predicate using the current date or current timestamp.

Use existing room hotel/active and hotel/usage/cleanliness indexes. At 100–500 rooms, filtering floor and cleanliness within one hotel's rooms is a small bounded operation. Do not add a separate floor index or duplicate room-state index in Step 1.

### 21.2 Query contracts

| Screen/query | Strategy |
|---|---|
| Operational queue | All unfinished tasks, including older days; bounded hotel predicate; join rooms by composite identity |
| Today's tasks | UTC timestamp range derived from hotel-local midnight and next midnight; include old unfinished work separately, without duplicates |
| Worker list | Hotel + assigned ERP ID + unfinished predicate; join room once |
| Floor list | Filter rooms by hotel/floor, join their current/unfinished task; do not denormalize floor on tasks |
| Dirty rooms | Hotel rooms with `kirli`, including rooms with NULL/cancelled task pointer |
| Pending inspections | Active vacant rooms joined through their pointer to `tamamlandi` tasks; never scan all historical completions |
| Room history | Hotel + room + creation/id cursor |
| Rack summary | One hotel and a bounded list of room IDs, joining only current task pointers |

Return 50 rows by default, with a hard page maximum of 100. Use keyset cursors rather than deep offsets. History cursor order is creation time and ID descending. Operational sorting is priority, non-NULL deadline first/ascending, creation time, then ID; sorting the bounded active set in memory is acceptable.

Use `pms_bugun` and the existing Europe/Istanbul assumption for local day boundaries. Return `sunucu_zamani` with list responses so UI age/overdue calculations are not based solely on a misconfigured phone clock. Do not wrap indexed task timestamps in a date conversion in the WHERE predicate; calculate the range boundaries once.

Fetch eligible employee display names once per hotel/page context and join maps in the client. List RPCs return only projected fields, not task/employee `SELECT *` or full reservation/guest histories. No N+1 requests or full-history client downloads.

Use one statement snapshot for a combined task/room list. Read-only consistency comes from PostgreSQL's snapshot plus atomic writers, not from a frontend reconciliation job.

### 21.3 Capacity and measurements

Test with synthetic datasets of 100, 500 and 2,000 rooms and at least 100,000 historical tasks. Confirm with execution plans that active/readiness queries are proportional to current hotel rooms or requested pages, not all historical rows. Set an initial staging goal of p95 below 300ms for ordinary list SQL and below 1 second for uncontended housekeeping command transactions; report environment and measured values rather than claiming production latency.

No table partitioning, cache service, scheduled materialized view or Realtime publication change is required. Polling is bounded and visible-tab-only. Additional indexes require measured query evidence after this baseline; initial implementation follows the fixed index set above.

## 22. Test Strategy

### 22.1 Test environment and assertions

Implement tests only in an isolated local/staging PostgreSQL/Supabase environment built from the accepted post-Phase-1 baseline plus the new migration. Use synthetic users/rooms/reservations; never production data or credentials.

Use three complementary layers:

1. SQL/catalog contract tests for types, keys, predicates, policies, grants, trigger activation/deferrability and function ACLs.
2. Real concurrent database sessions with barriers that place transactions at known lock boundaries. Do not use timing-only sleeps as the proof of a race.
3. PostgREST tests with real role/JWT contexts for public RPCs and direct table attempts. A successful superuser test does not prove RLS or REST behavior.

Fixtures include two hotels with identical room numbers, home-hotel workers, an all-hotel worker, supervisors, a reception user, an active user without housekeeping permission, an inactive user, an Auth identity without an ERP row, and anon. Include occupied overdue stays and historical completed/cancelled tasks.

Each failure assertion checks its intended cause and verifies task, room, reservation and audit state from a fresh connection after commit/rollback. RLS SELECT denial may be an empty set; DML ACL denial is an error. Do not accept a wrong error as evidence that the intended invariant worked.

### 22.2 Required behavioral tests

| # | Scenario | Required result |
|---|---|---|
| 1 | Checkout → dirty room + task | Reservation checked out, room vacant/dirty, one current waiting checkout task with exact source, one transaction's audit evidence |
| 2 | Duplicate active task | Two different creation intentions cannot leave two unfinished tasks; unique index is asserted |
| 3 | Two-worker claim race | Exactly one owner/version increment; losing worker cannot start |
| 4 | Assignment versus assignment/start | One version wins; no start under a replaced assignee |
| 5 | Start | Own waiting task becomes running; room becomes `temizleniyor`; one server stamp |
| 6 | Complete | Own running task becomes completed; room `temiz`; assignee and start preserved |
| 7 | Inspection | Different supervisor certifies current completed vacant room; room `kontrol_edildi` |
| 8 | Dirty check-in | Rejected; reservation/assignment/room/audit unchanged |
| 9 | Clean check-in | Accepted under Phase 1 constraints; current pointer retired |
| 10 | Inspected check-in | Accepted; pointer retired; historical inspection intact |
| 11 | Cross-hotel room/source/predecessor | Composite FK rejects wrong hotel and wrong room even in a trusted-writer integrity test |
| 12 | Cross-hotel worker assignment | Home-hotel foreign worker rejected; eligible all-hotel worker accepted |
| 13 | Unauthorized caller | Every public action and read surface respects its module/level and hotel |
| 14 | Inactive/missing ERP caller | Denied; valid Auth token alone is insufficient |
| 15 | Complete versus check-in, both orderings | Only serially valid outcomes; no occupied room admitted while still dirty/cleaning |
| 16 | Cancellation | Room stays dirty; running start/assignee retained; cannot cancel completed work or revive cancelled row |
| 17 | Reassignment and handover | Waiting reassignment preserves waiting state; running reassignment denied; handover creates one successor atomically |
| 18 | Retry/idempotency | Creation after terminal state returns original row; immediate claim/start/complete/inspect replay has no side effects; later stale request conflicts |
| 19 | Direct DML | Task POST/PATCH/upsert/DELETE denied; arbitrary room cleanliness/pointer and combined cleanliness+occupancy spoof rejected |
| 20 | Audit transactionality | Inject task/room/audit/late-constraint failures; all business and audit changes roll back together |
| 21 | Block/fault behavior | Claim/start denied while blocked; running work cancelled on restriction; dirty release creates/reuses exactly one task |
| 22 | Checkout with current stayover work | Old waiting/running attempt cancelled; new turnover task, never renamed old task |
| 23 | Old completion/inspection/rework | A historical non-current task cannot affect a newer cycle, including after check-in/checkout |
| 24 | Rework race | Same or different request keys cannot produce two successors; previous completion remains immutable |
| 25 | Actual occupancy versus dates | Overdue checked-in stay still supports stayover service and valid checkout; Rack lookup agrees |
| 26 | Employee scope/deactivation race | Scope reduction and assignment serialize; deactivation prevents subsequent execution without deleting history |
| 27 | Wrong command-key payload | Same key with changed action/notes/target/version fails; timestamps/version/audit unchanged |
| 28 | Failure halfway through replacement | Old cancellation rolls back if new task, pointer or audit fails; no half-handover |
| 29 | Module disable/enable | New user commands and production stop; lifecycle invalidation still works; running/dirty rooms remain fail-closed; history survives |
| 30 | Legacy activation | Orphan `temizleniyor` baseline blocks activation; clean/dirty NULL-pointer rooms follow the documented adoption contract |
| 31 | Shared audit compatibility | Existing non-housekeeping audit callers retain CRUD/actor/transaction behavior and NULL details |
| 32 | Permission-isolated worker UI reads | Worker without user-management/guest/reservation privileges can read required sanitized housekeeping data only |
| 33 | Disabled producer fault recovery | With module off and only producers disabled, checkout remains valid/dirty, final task-room invariants still hold |
| 34 | Mobile/Rack error handling | HTTP failure never yields success UI; network retry reuses receipt; stale card refreshes; no per-room requests |
| 35 | Search-path and role boundary | Application roles cannot assume owner or call private helpers; shadow names cannot redirect definer operations |
| 36 | Clock and day boundaries | Post-lock server timestamps remain ordered; Istanbul midnight and old unfinished tasks are represented correctly |
| 37 | Manual creation versus check-in | Creation first makes the room dirty and blocks admission; check-in first invalidates a stale expected-vacant creation request |
| 38 | `pms_odalar` BEFORE trigger order | Catalog query returns exactly the five expected names with `pms_housekeeping_oda_koruma` second; a renamed guard fails the assertion (13.3.1) |
| 39 | `pms_odalar` privilege tightening | As the real `authenticated` role: SELECT/INSERT/UPDATE still work, check-in/check-out/Rack unaffected; TRUNCATE/REFERENCES/TRIGGER no longer granted (13.4.1) |
| 40 | Creation origin CHECK matrix | `kullanici` without `olusturan` rejected; `sistem` with NULL `olusturan` accepted; `checkout` origin and `cikis_temizligi` type cannot be separated; origin immutable after insert (4.1.1) |
| 41 | Internal receipts | A producer/invalidator mutation leaves non-NULL `son_islem_anahtari`/`son_islem_ozeti`; a REST caller cannot supply an internal action, origin or key; internal receipt never enables client replay (12.4) |
| 42 | Shared hotel immutability on tasks | `phase0_otel_degismez` present on the task table and rejects an `otel_id` update even under a trusted fixture writer (4.4.1) |
| 43 | Module record completeness | Installed row has `kategori = 'onburo'`, correct `sira`, `aktif = false`; while inactive, every housekeeping read and command is denied through `auth_yetki_var` (16.1) |

Run races for both winners and under the complete Phase 1 trigger graph. Include checkout source uniqueness after the first task has been cancelled or completed, not only while it is active.

### 22.3 Regression and release gates

Run the relevant existing room/reservation/check-in/out and folio regression suites in the isolated environment. Verify existing financial immutability, checkout behavior and source assignment exclusions have not been weakened. Run the migration static checker and its sabotage suite. No test command in this specification is authorization to execute it against production.

Acceptance requires passing behavior tests, expected catalog definitions, unmutated baseline security zeros, and the sabotage evidence in the next section. A browser-only success is insufficient.

## 23. Sabotage Tests

**Decision:** Prove the tests fail when each required protection is removed, in disposable test databases only.

**Reason:** RPC prechecks or another constraint can accidentally mask a missing security layer and let a weak test remain green.

**DB enforcement:** The intact system enforces the tested invariant; the sabotage harness removes one targeted layer and expects a specific catalog and/or behavioral assertion to fail.

**Failure prevented:** Tests that pass for the wrong reason or never exercise the protection they claim to verify.

| Mutant | Isolated probe and expected detection |
|---|---|
| Remove `pms_housekeeping_aktif_oda_uniq` | Catalog test identifies missing/wrong predicate. A layer test inserts two otherwise-valid unfinished task rows under a trusted fixture writer with higher-level orchestration excluded; unique-layer assertion must fail |
| Remove task transition protection | With valid hotel, actor, timestamps and consistent room projection, attempt waiting → completed directly through a trusted fixture writer. Intact guard rejects; mutant permits the forbidden transition and fails the assertion |
| Remove restrictive hotel scope | In the test fixture add an intentionally permissive read policy. Intact restrictive policy still hides another hotel; removing it leaks a foreign row and fails the read assertion |
| Remove RPC hotel check | Use a same-permission foreign-hotel actor against a valid foreign task; because the definer bypasses RLS and the record's own FKs are valid, the test specifically detects missing caller scope |
| Remove composite hotel/room FK | Use a structurally wrong hotel or room/source pairing under a trusted fixture writer; the reference test and exact FK-column catalog assertion fail |
| Remove command authorization | Active same-hotel user without housekeeping permission invokes a valid supervisor operation through its granted RPC entry point. Intact common authorization rejects; mutant succeeds and fails the test |
| Remove room/task consistency checks | Perform a row-valid running → completed transition while intentionally omitting the room projection. Intact deferred checker rejects commit; mutant commits task-completed/room-cleaning and fails H5 verification |
| Remove current-pointer protection | Try inspecting an old completed task after a newer cycle/check-in. The stale-cycle test must fail on the mutant |
| Remove audit trigger or swallow audit failure | Catalog audit binding and rollback/event assertions fail; business success without the required audit is detected |

Layer tests are explicitly test-only fixtures. They may bypass wrapper routing or other redundant layers to reach the layer under test, but never modify production or the deliverable migration. The unique-index probe isolates uniqueness because room-pointer consistency would otherwise reject the second row for another reason. Both the intact and mutant fixture use the same controlled exclusions, with the target protection present only in the intact fixture.

For each mutant:

1. Assert the sabotage target matched exactly the expected object/count; missing targets are test setup failures, not green tests.
2. Prove the intact fixture passes the protection-specific test first.
3. Apply one targeted mutation to a fresh disposable database/candidate copy.
4. Check the exact expected failing assertion/error category; an unrelated permission, missing-table or connection error does not count.
5. Record expected versus observed failure, then discard the mutant environment.

Authorization and tenant scope have redundant defenses. If removing one layer remains behaviorally masked, its structural contract must still fail and a layer-isolated probe must demonstrate its role. Never demand that removing one guard make the entire production design exploitable just to obtain a red test.

## 24. Rollback / Feature Disable

### 24.1 Ordinary module disable

**Decision:** Disable the existing `pms_housekeeping` module flag before considering destructive rollback. Keep history and integrity guards.

**Reason:** Removing tables or broadly disabling triggers could destroy operational evidence or reopen the old direct-cleanliness bypass.

**DB enforcement:** Public reads/commands check module permission; automatic producers explicitly lock/read module active state; lifecycle invalidators and consistency constraints remain installed.

**Failure prevented:** Invisible work production, orphan running tasks and accidental return to inconsistent legacy writes.

The disable transaction changes only `moduller.aktif` for this module. Its write lock waits for in-flight housekeeping/producer transactions holding the shared module lock to finish. It must not acquire room/task locks in that transaction. After it commits:

- New housekeeping task reads and public mutations are denied.
- Checkout still performs core checkout and leaves a vacant dirty room.
- Checkout invalidates/cancels conflicting unfinished work and clears the pointer, but creates no new task.
- Dirty-room release creates no task.
- Existing history remains stored.
- Existing running work is not silently marked completed or clean. It remains fail-closed until re-enabled or legitimately invalidated by checkout/block/fault/inactivation.
- Existing clean/inspected rooms may still pass normal check-in; their pointer retirement and core checks continue.

**Disabling is not a complete restoration of the old Phase 1 cleaning UI.** Direct cleanliness PATCH remains blocked. Dirty/running rooms cannot be made ready through housekeeping while the module is off. Operations must re-enable a repaired module before ordinary room-turnover work resumes. Make this business impact explicit in the operational runbook.

### 24.2 Automatic triggers and emergency isolation

Definer triggers do not automatically stop because module permissions stop. This design requires explicit enabled-state checks in both producers: reservation checkout creation and dirty-room release creation.

The always-on room lifecycle invalidator and the disabled-mode checkout invalidation path continue to run. They may cancel invalidated work and retire pointers, but cannot create or complete work while disabled. Audit remains transactional for these necessary lifecycle changes.

If a producer itself is defective, the later approved recovery operation is:

1. Disable the module and drain in-flight commands.
2. Disable only the named task-production hooks, not integrity, audit or lifecycle invalidation hooks.
3. The separately installed lifecycle invalidator still handles checkout's `dolu` → `bos` transition: cancel current unfinished work, leave dirty, and retain the cancelled pointer; or clear a pointer that was already terminal. A retained cancelled pointer is consistent with H7 and needs no producer to be valid.
4. Verify disabled-mode checkout/block/fault/check-in behavior in staging before selecting that recovery procedure.
5. Repair through a new forward migration and re-enable the producer before re-enabling the module.

The supersession contract is the same whether or not a producer runs: room invalidation cancels unfinished work and retains that cancelled pointer; it clears already-terminal pointers. A running producer verifies the retained cancellation reason and its exact stay source, then replaces the pointer when enabled or clears it when the module is disabled. If the producer hook is itself disabled, the cancelled pointer simply remains as dirty-room evidence. It cannot be inspected, completed or bypass check-in. No trigger-catalog mode switch, client flag, audit-log lookup or extra configuration table is needed.

Do not use a broad `DISABLE TRIGGER ALL`, disable `ensure_rls`, remove FKs, drop audit or grant direct task/cleanliness DML as rollback. The separate producer/invalidator hooks and their enabled-state interaction are required test targets, not optional deployment conveniences.

### 24.3 Re-enable and destructive rollback boundary

Before re-enable, inspect staging-tested invariant reports for orphan running rooms, unfinished tasks not pointed to by rooms, invalid employee assignments and dirty rooms without tasks. Historical tasks remain unchanged. Re-enable producer hooks, confirm their definitions and ACLs, then enable the module in its flag-only transaction.

Dirty rooms accumulated while disabled remain explicit backlog and receive supervisor-created extra tasks after enablement. Do not invent old checkout timestamps or retroactively claim they were auto-created. Current active tasks resume only after actor/room/version revalidation.

A failed migration transaction rolls back atomically. After committed operational history exists, DROP TABLE is not the normal rollback. Any future destructive restoration requires a separately approved recovery design and protection of later reservations, folio and payment data. A whole-database restore is not a housekeeping feature toggle.

## 25. Risks and P0/P1 Concerns

| Priority | Concern | Required treatment |
|---|---|---|
| P0 | Phase 1 room-first checkout versus new constraints | New cross-table checks initially deferred and final-row based; integration tests run full checkout |
| P0 | Old completed task can certify a new cycle | Composite current pointer, check-in retirement and stale-cycle checks |
| P0 | Existing authenticated room grants are table-level **ALL**, not UPDATE | Invoker room-route guard; no misleading column-revoke-only protection; TRUNCATE bypasses row triggers but is not PostgREST-reachable; forward revoke of TRUNCATE/REFERENCES/TRIGGER per 13.4.1 |
| P1 | BEFORE trigger firing order on `pms_odalar` is name-dependent | Fixed name and position per 13.3.1, asserted by catalog test 38 |
| P1 | Producer paths have no authenticated ERP actor | Nullable `olusturan` bound to immutable `olusturma_kaynagi` by CHECK (4.1.1); server-generated internal receipts (12.4); no sentinel user |
| P0 | Hidden rows in trigger queries | Definer invariant readers; no caller-RLS false absence |
| P0 | Source FK implicit lock inversion | Acquire stay source prefix before room when establishing references |
| P0 | Worker scope changes during assignment | Employee SHARE lock and scope-change guard; no reverse room locks |
| P0 | Checkout/task/audit failure coupling | Atomic rollback and tested producer disable path |
| P0 | Disable skips producer but strands active work | Separate always-on lifecycle invalidation with deterministic checkout handoff |
| P0 | Shared audit writer extension | Explicit opt-in behavior, allowlisted details and legacy regression tests |
| P0 | Migration adoption of legacy running rooms | Precondition and approved operational cutover; no fabricated history |
| P0 | Source assignment historical mutation | Composite restrictive reference; surface the intentional stronger historical-reference restriction |
| P1 | Generic HTTP helper does not throw on HTTP errors | Shared adapter explicitly checks HTTP/application success |
| P1 | Rack treats planned departure as actual vacancy | Align touched occupancy lookup with server actual-stay definition |
| P1 | Today-only queue loses yesterday's work | Always include old unfinished tasks; date filter only for historical/today view |
| P1 | Growing history makes room/worker queries expensive | Fixed bounded query contracts and measured initial indexes |
| P1 | Duplicate transition logic in RPCs/triggers/UI | One private transition/projection implementation; guards validate; UI never owns state |
| P1 | Target-user eligibility duplicates caller helper conditions | One narrow adapter over existing auth tables plus equivalence tests for home/all-hotel users |
| P1 | New state or task type added casually | Versioned contract/test update; CHECK and transition definitions must change together |

The chosen current-pointer and receipt columns add limited schema complexity. They are retained because they prevent identifiable stale-cycle and retry failures. Avoid adding independent task-active flags, inspection-task queues, employee-membership tables or generic workflow engines on top.

Known Supabase default-ACL, event-trigger ownership and platform BYPASSRLS risks remain documented baseline concerns. They are not expanded into a platform-hardening project here. No new realtime, extensions, platform roles or production credential handling is required.

All measurements in this document are source/baseline facts or explicitly labelled staging targets. Architecture acceptance does not claim implementation tests or production migrations have run.

## 26. Recommended Build Order

These are future implementation steps. They are not authorization to create implementation files or change production during this documentation task.

1. **Freeze contracts and acceptance fixtures.** Use the decisions, H1–H10, state matrix, API payloads and expected role behavior in this document. Prepare synthetic two-hotel, overdue-stay and legacy-room fixtures.
2. **Create the new forward migration in staging.** Add the task table, room pointer, assignment target key, CHECK/FK/unique/index contracts, immutable guards and exact ACL/RLS policies. Verify catalog assertions before exposing commands.
3. **Implement the private command/projection engine and public RPCs.** Enforce lock order, expected versions, receipts, actor ownership and deterministic room projection; test direct-DML and state transitions.
4. **Implement lifecycle integration as a unit.** Add room invalidation, reservation checkout production and dirty-release production, plus initially-deferred consistency triggers. Test their normal, disabled and producer-disabled orderings before UI work.
5. **Integrate existing audit.** Add opt-in detail capture and test legacy callers, replacements and rollback-on-audit-failure.
6. **Implement sanitized bulk reads and eligibility adapter.** Confirm a housekeeping-only worker can operate without guest/reservation/user-management access. Measure bounded query plans.
7. **Build mobile UI and shared RPC adapter.** Handle network ambiguity, versions and nonthrowing HTTP errors. Include unavailable-worker, blocked-room and taskless-dirty exceptions.
8. **Update Room Rack and navigation.** Remove direct cleanliness PATCH behavior, align actual-occupancy lookup and use the same task API.
9. **Run database, concurrent-session, REST and sabotage suites.** Include Phase 1 regression and migration-checker gates. Fix failed invariants rather than weakening expected errors.
10. **Prepare the approved rollout/disable runbook.** Record the legacy-running-room precondition, role grants, module activation ordering and producer-isolation recovery. Confirm complete staging rollback/disable behavior.
11. **Prepare a new baseline and approved implementation documentation updates.** Preserve historical Phase 1 artifacts. The project's later documentation-sync workflow may update the Obsidian vault with wikilinks, but this task creates only this one Markdown document.
12. **Deployment remains separately authorized.** The eventual production operation follows the existing migration security and release process; nothing in this specification performs it.

Expected future implementation file surface: one new Phase 2 SQL migration, `pms-housekeeping.html`, a small shared `pms-housekeeping.js`, targeted `pms-oda-plani.html` and `nav-drawer.js` changes, focused SQL/Node test files, and a new approved Phase 2 fingerprint. Existing Phase 1 migration contents remain hash-locked.

## 27. Implementation Checklist

### Database and lifecycle

- [ ] One historical task table with the exact required/conditional columns and immutable fields.
- [ ] One unfinished task per room, enforced by the partial unique index over waiting/running only.
- [ ] Composite hotel/room/source/predecessor/pointer references; restrictive historical deletion behavior.
- [ ] CHECK-constrained text types and the exact five-state matrix; no assigned state or task-active flag.
- [ ] Completed attempts immutable except current-cycle optional inspection; rework is a unique successor.
- [ ] One post-lock server timestamp per operation and positive version increments.
- [ ] `olusturma_kaynagi` immutable, CHECK-bound to `olusturan` presence and task type; no sentinel ERP user created.
- [ ] Internal mutations generate their own key/fingerprint server-side; receipt columns non-NULL on every path.
- [ ] Shared `phase0_otel_degismez` trigger installed on the task table.
- [ ] `pms_odalar` BEFORE trigger order asserted by catalog test, not assumed.
- [ ] Module row carries `kod`/`ad`/`kategori`/`sira`/`aktif` explicitly, installed inactive.
- [ ] Room readiness projection and H1–H10 enforced from both task and room sides.
- [ ] New consistency constraints initially deferred and reading final rows.
- [ ] Check-in accepts clean/inspected old readiness, rejects spoofed cleanliness and retires the pointer.
- [ ] Occupied stayover work retains usage `dolu` and uses actual stay context.
- [ ] Checkout source task creation/replacement/audit occurs in the checkout transaction.
- [ ] Block/fault/inactive lifecycle behavior and dirty-release reuse/create are implemented exactly.

### Concurrency and API

- [ ] Employee/source/room/task/module lock order includes implicit FK locks.
- [ ] No task-first writes or source-lock acquisition after a room lock.
- [ ] Worker claim is self-only and cannot steal; reassignment is waiting-only.
- [ ] Running handover and rework are atomic, linked and retry-safe.
- [ ] Permanent creation receipt, natural checkout source and predecessor uniqueness are independently tested.
- [ ] Mutation receipt checks precede stale-version rejection for an exact latest-command replay.
- [ ] Intervening-work replay returns a conflict rather than silently applying against a newer version.
- [ ] Unexpected integrity/audit errors are never swallowed as successful no-ops.

### Security and audit

- [ ] Explicit TABLE/FUNCTION ACL revocations include inherited application privileges.
- [ ] Authenticated task SELECT only; no public task DML or service-role bypass API.
- [ ] Restrictive hotel RLS and operation-specific SELECT policy are fail-closed.
- [ ] Active ERP identity, actual hotel scope and action-level permission checked at public boundaries.
- [ ] Target employee checked against existing home/all-hotel and permission-matrix authority.
- [ ] Employee scope-reduction race guarded; deactivation prevents execution without deleting history.
- [ ] Definer paths pinned, qualified and sealed; invoker room guard preserves caller-role distinction.
- [ ] Existing room DML grants cannot bypass cleanliness or pointer protections.
- [ ] Existing audit reused with opt-in allowlisted details; no full-row or note/guest snapshots.
- [ ] Audit failure rolls back task, room and source checkout; legacy audit behavior remains tested.
- [ ] Static checker, runtime catalog assertions and baseline security zeros pass.

### UI, operational readiness and completion evidence

- [ ] Mobile worker/supervisor/reception flows use the same bounded RPC contract.
- [ ] Room Rack contains no independent cleanliness PATCH/next-state authority.
- [ ] Dirty taskless rooms, blocked work and unavailable assignees are visible.
- [ ] HTTP failures cannot show success; ambiguous network retries preserve request identity.
- [ ] Queries include old unfinished work, use hotel predicates and avoid N+1/history downloads.
- [ ] All required races have both serial orderings tested with deterministic synchronization.
- [ ] Every sabotage mutant produces its intended failed assertion, not an unrelated error.
- [ ] Module disable drains commands, stops production, preserves invalidation/audit and retains history.
- [ ] Producer-only emergency disable is tested without disabling integrity or platform triggers.
- [ ] Legacy running rooms are resolved before activation; no historical task fabrication.
- [ ] Phase 1 regression, focused performance measurements and new baseline deltas are recorded.
- [ ] Implementation and any production deployment receive their separate required authorization.

**Architecture completion criterion:** An implementation is conformant only when the database invariants, security boundaries, transaction outcomes, retry behavior and disable behavior above are demonstrated by the specified tests. UI resemblance alone is not acceptance.

PMS PHASE 2 HOUSEKEEPING ARCHITECTURE READY
