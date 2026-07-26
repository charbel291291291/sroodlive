# Frame Management v2 — Admin Workflow Redesign · Final Report

Date: 2026-07-26 · Branch: `audit/supabase-migration-history` · **Not committed, not pushed, not deployed.**

Goal: an admin adds a professional static or animated avatar frame in under a minute.
The editor now needs only **name → category → unlock rule → upload a `.webp`/`.png` → Save**;
every other `frame_catalog` column is either auto-derived or reachable under a collapsed
**Advanced** section, so nothing that existed before was dropped.

---

## 1. Files changed

### New — migration

| File | Lines |
|---|---|
| `supabase/migrations/20261133000000_frame_artwork_storage_and_create_rpc.sql` | 203 |

> The plan's placeholder filename was `20261125000000_…`. That slot was already taken by
> `20261125000000_remove_srood_blocks.sql`, so the migration landed at the next free
> version, `20261133000000`. Nothing else about it changed.

### New — Dart

| File | Lines | Purpose |
|---|---|---|
| `lib/features/admin/frames/frame_editor_form.dart` | 544 | All editor rules as pure Dart: code generation, `nextSortOrder`, `FrameEditorState`, `validate()`, `toFrame()`, `duplicateFrom()`, `kFrameRequiredRoles` |
| `lib/features/admin/frames/frame_editor_dialog.dart` | 1137 | The dialog: sticky header, scrollable body, sticky footer, responsive two→one column |
| `lib/features/admin/frames/frame_artwork_field.dart` | 238 | Upload / Replace artwork control, size + dimension readout, warnings vs errors |
| `lib/features/admin/frames/frame_live_preview.dart` | 321 | Live preview at three sizes over dark/light, animate toggle |
| `lib/features/admin/services/frame_artwork_upload_service.dart` | 518 | Validation + upload + orphan delete, with injected storage seams |
| `lib/features/admin/exceptions/frame_admin_exception.dart` | 310 | Typed error categories + `mapFrameAdminError` |
| `lib/features/admin/theme/frame_admin_theme.dart` | 156 | The existing dark-luxury palette extracted so the new widgets share it |
| `lib/core/frames/frame_catalog_sync_service.dart` | 135 | `frame_catalog` → `FrameRegistry.hydrate()`, TTL + single-flight, never throws |

### Rewritten / modified

| File | Change |
|---|---|
| `lib/features/admin/screens/frame_management_screen.dart` (1094) | List rewritten: thumbnail rows, Duplicate action, three-kind filters, search over name/code/legacy key, parallel reload, optimistic active toggle, typed errors. `_FrameEditorSheet` replaced by the new dialog. Route unchanged. |
| `lib/features/admin/services/frame_admin_service.dart` (226) | Added `FrameAdminRpcCaller` seam, `createFrame()`, `frameCodeExists()` |
| `lib/core/frames/srood_frame.dart` | Added read-only `legacyFrameKey` (+ `fromJson`) |
| `lib/core/frames/frame_registry.dart` | Added `specForFrame()` and `resetToBuiltIns()` |
| `lib/shared/widgets/srood_avatar_frame.dart` (329) | One additive, default-null `frameOverride` parameter. Every existing call site is unaffected. |
| `lib/features/home/home_screen.dart` | One fire-and-forget `FrameCatalogSyncService.instance.load()` beside the existing flag load |

### New — tests

| File | Lines |
|---|---|
| `test/features/admin/frames/frame_editor_form_test.dart` | 712 |
| `test/features/admin/frames/frame_artwork_upload_service_test.dart` | 516 |
| `test/features/admin/frames/frame_admin_service_payload_test.dart` | 374 |
| `test/features/admin/frames/frame_editor_dialog_layout_test.dart` | 425 |
| `test/features/frames/frame_catalog_sync_service_test.dart` | 292 |
| `test/contracts/frame_artwork_storage_contract_test.dart` | 235 |

---

## 2. New migration — what it adds

`20261133000000_frame_artwork_storage_and_create_rpc.sql`, additive only. It does **not**
touch `frame_catalog`, `avatar_frames`, `user_avatar_frames`, `user_frames`,
`frames_v2_user_can_use`, or any of the 29 existing catalog rows, and it edits no
already-applied migration.

**1. Storage bucket `avatar-frames`** — `public = true` (frames render on pre-auth and
public surfaces, like the `avatars` bucket), `file_size_limit = 2097152` (2 MB, the
animated-WebP ceiling), `allowed_mime_types = array['image/webp','image/png']`,
`on conflict (id) do update set …` so a re-run cannot fail a deploy.

**2. Four `storage.objects` policies** — `avatar_frames_select` (`to anon, authenticated`,
`using (bucket_id = 'avatar-frames')`) and `avatar_frames_insert` / `_update` / `_delete`
(`to authenticated`, each `bucket_id = 'avatar-frames' and public.has_admin_access()`).
Each is preceded by `drop policy if exists` so the migration is re-runnable.

**3. `public.admin_create_frame_v2(...)`** — the same 20 parameters as
`admin_upsert_frame_v2`, in the same order, **without** the `on conflict (code) do update`
clause. It raises `not_authorized` when `public.has_admin_access()` is false,
`invalid_vip_config` / `invalid_role_config` on contradictory input (including
`p_vip_level <> p_required_vip_level`), and `frame_code_exists` on `unique_violation`.
It mirrors the additive legacy `avatar_frames` row that `profiles.selected_avatar_frame_key`'s
FK needs, writes `admin_audit_logs` with `action = 'create_frame_v2'`, runs
`security definer set search_path = ''`, and ends with
`revoke all … from public; grant execute … to authenticated;`.

`admin_upsert_frame_v2` is untouched and still serves updates.

**Deployment status: NOT applied anywhere.** No remote deploy without your approval.

---

## 3. Storage bucket / policy changes

- Bucket created: **`avatar-frames`** (did not exist in any prior migration).
- Object path: `{category}/{frame_code}/v{millisecondsSinceEpoch}.{ext}` inside that bucket
  — i.e. `avatar-frames/vip/vip4_celestial_crown/v1753526400000.webp`.
- Upload options: `contentType` derived from the extension, `upsert: false`,
  `cacheControl: '31536000'` — safe because every path is version-stamped and immutable.
- Client-side validation (all inside the service, so no call site can skip it): extension
  allowlist `webp`/`png`, MIME allowlist, empty-file rejection, **400 KB static target
  (warning)**, **1 MB static hard limit (error)**, **2 MB animated hard limit (error)**,
  non-square warns without blocking.
- Animation and dimensions are read by parsing the PNG/WebP container headers in pure Dart
  rather than via `dart:ui` — a deliberate change from the plan, so validation needs no
  Flutter binding and never decodes a full bitmap just to read a size.

---

## 4. RPCs used

| RPC | Used for | Status |
|---|---|---|
| `admin_create_frame_v2` | Creating a new frame (fails loudly on a duplicate code) | **New in this migration** |
| `admin_upsert_frame_v2` | Editing an existing frame | Pre-existing, unchanged |
| `admin_assign_frame_v2` | Grant a frame to a user | Pre-existing, unchanged |
| `admin_revoke_frame_v2` | Revoke a frame | Pre-existing, unchanged |
| `admin_frame_ownership_history_v2` | Ownership history panel | Pre-existing, unchanged |
| `admin_set_frame_enforcement_v2` | Enforcement toggle | Pre-existing, unchanged |
| `frames_v2_migration_report` | Migration status panel | Pre-existing, unchanged |
| `get_frame_catalog_v2` | Catalog read for the admin list **and** for registry hydration | Pre-existing, unchanged |

No delete RPC exists; frames are deactivated (`is_active = false`), never deleted.

---

## 5. Security decisions

- **No service-role key, no privileged key, anywhere in Flutter.** The app uses only the
  anon key it already ships with.
- **No direct client writes to `frame_catalog`.** It still has SELECT-only RLS and zero
  write policies; every write goes through a `security definer` RPC gated on
  `public.has_admin_access()` (app role `admin` or `super_admin`).
- **Storage writes are gated on the same predicate as the catalog RPCs**, so an account can
  never upload artwork it could not also register — no half-authorized state.
- **`security definer set search_path = ''`** with fully-qualified references in the new
  function, the safer of the two conventions present in this repo.
- **Overwrite protection is server-side, not just client-side.** The client pre-checks the
  code for a fast, readable error, but the authoritative guard is the plain `insert` +
  `unique_violation` → `frame_code_exists` in `admin_create_frame_v2`. A stale or modified
  client cannot silently overwrite another admin's frame.
- **VIP/role contradictions are rejected server-side too** (`invalid_vip_config`,
  `invalid_role_config`), not only in the form.
- **Replace-artwork ordering** (requirement 9): upload new object → call the RPC → only on
  RPC success adopt the new URL. On RPC failure the DB row is untouched and the *new*
  orphan is deleted; if that cleanup itself fails it is logged and surfaced. **The old
  object is never deleted before the database update succeeds.**
- **No raw Postgres text as the only message.** Every catch routes through
  `mapFrameAdminError` (`duplicateCode`, `notAuthorized`, `sessionExpired`,
  `invalidVipConfig`, `unsupportedFormat`, `fileTooLarge`, `storagePolicy`, `network`,
  `constraintViolation`, `unknown`); the raw exception goes only to `debugError`.
- **Client-side `frames.manage` check on entry**, layered on top of the server gate — never
  instead of it. (See the limitation in §8.)
- **Role vocabulary was not invented.** The role dropdown offers exactly the ten
  `app_user_roles_role_check` values. `agency_owner` / `recharge_owner` / `room_owner` /
  `host` are frame *categories*, not roles, and are never used as `required_role`.
- **Category filters use only values the existing CHECK allows.** "Mythic" is filtered as a
  `rarity` and "Role-based" as an `unlock_type`, because neither is a valid category.

---

## 6. Tests executed and results

All four commands were run on this machine. Nothing below is inferred.

**`dart format`** (scoped to this task's files) → `Formatted 29 files (1 changed)`.
An earlier, wider format pass had reflowed three unrelated admin files; those were verified
to be formatting-only diffs and reverted with `git checkout --`, honouring *"do not modify
unrelated features."*

**`flutter analyze`** → **7 issues**: 6 pre-existing `curly_braces_in_flow_control_structures`
infos in files this task never touched, plus 1 unused-import warning of mine — **which was
removed**. No warnings or errors remain in any file this task owns.

**`flutter test test/features/admin/frames test/features/frames test/contracts`**
→ **`00:12 +229: All tests passed!`**

Two earlier runs of the same command failed and drove real fixes (§7): run 1 was 204 pass /
25 fail, run 2 was 225 pass / 4 fail, run 3 was clean.

**`flutter test`** (whole suite) → **`00:54 +477 ~1: All tests passed!`** — 477 passed,
1 skipped, 0 failed. No pre-existing test was broken.

**SQL / local migration validation: NOT EXECUTED.** No Supabase CLI or local Docker run was
attempted, so the migration's SQL has not been executed anywhere. It is covered only by the
string-level contract test (`test/contracts/frame_artwork_storage_contract_test.dart`,
21 tests over the bucket id, public flag, 2 MB limit, MIME allowlist, the four policy
names, `has_admin_access()` in every write policy, the 20 RPC parameters, the absence of
`on conflict` on the catalog insert, the grant/revoke tail, and a banned-statement list).
Executing it against a real Postgres is an outstanding step.

### What the suites cover

- **`frame_editor_form_test.dart`** — `Celestial Crown` + VIP 4 → `vip4_celestial_crown`,
  Arabic / empty / punctuation names, `^[a-z0-9_]+$` conformance, `_2`/`_3` de-duplication;
  `nextSortOrder` = per-category max + 10; the four forbidden VIP/role combos; VIP field
  clearing; `duplicateFrom` leaving the source row untouched.
- **`frame_artwork_upload_service_test.dart`** — bad extension, bad MIME, zero bytes,
  1.2 MB static rejected, 900 KB static warned, 2.5 MB animated rejected, non-square warns
  and passes, path format, `cacheControl` present, and the orphan delete firing **after** a
  simulated RPC failure and **not** before it.
- **`frame_admin_service_payload_test.dart`** — the exact 20-key create and update payloads,
  with `p_thumbnail_url` / `p_animation_url` / `p_unlock_value` / `p_required_level`
  non-null. That last one is the regression test for the data-loss bug: the old screen
  built its `SroodFrame` without those four fields, so editing any of the 29 live frames
  wiped them.
- **`frame_editor_dialog_layout_test.dart`** — the dialog opened at 1920×1080, 1366×768,
  1280×800, 800×600 and 390×844 with `expect(tester.takeException(), isNull)`, Save findable
  and hit-testable without scrolling at each size, surface reset in `tearDown`.
- **`frame_catalog_sync_service_test.dart`** — hydration merges rows, `resetToBuiltIns`
  drops a deactivated frame, an RPC error never throws, TTL refetch, single-flight.

---

## 7. Two production bugs found and fixed *by* the tests

Both were found only because the layout suite runs the real dialog, and both are genuine
defects rather than test artefacts:

1. **The Advanced section asserted in debug builds.** The `ExpansionTile` sat inside a
   coloured `DecoratedBox`; an `ExpansionTile` header is a `ListTile`, which paints its
   background and ink on the nearest `Material` ancestor, so Flutter raised *"ListTile
   background color or ink splashes may be invisible."* Fixed by making the container a
   `Material` (`color:` + `shape:` + `clipBehavior: Clip.antiAlias`).
2. **The footer could overflow.** Cancel + Save were a `Row` with
   `MainAxisAlignment.end` and overflowed by 30 px at 390×844 under the test font. Fixed
   with a `Wrap`, so the buttons stack rather than overflow at any width or text scale, and
   Save is always reachable.

Note on the second: flutter_test's default font renders every glyph as a full em square, so
`'Save changes'` measured 169 px there versus far less with Roboto. The overflow as measured
was a test-font artefact — but the same overflow is genuinely reachable with a long label or
a large accessibility text scale, so the widget was hardened rather than the test relaxed.

---

## 8. Remaining limitations

1. **A plain `admin` gets a read-only screen.** The new client-side `kPermFramesManage`
   (`'frames.manage'`) check grants management to `o_super_admin`, `p_super_admin` and
   `super_admin` only — `kRoleAdmin`'s permission set in `admin_access_service.dart:141-150`
   does not include it. The **server** (`has_admin_access()`) *would* accept an `admin`.
   So an `admin`-role user sees the list but cannot edit, even though their writes would
   succeed. This is a deliberately conservative client gate; widening it is a one-line
   change to that permission set, and is your call.
2. **Role-gated frames only unlock via `public.app_user_roles`.** `frames_v2_user_can_use`
   matches `required_role` against that table, but the live admin role system writes
   `public.admin_users`. An admin present only in `admin_users` will never unlock a
   role-gated frame. Per your decision, the UI was built and the server left untouched —
   this remains a **blocking gap for role frames** until the server side is reconciled.
3. **Uploaded frames do not reach users until `frames_v2_rendering_enabled` is `true`**
   (currently `false`). Hydration is wired, but the flag still gates user-facing rendering.
4. **Lottie `.json` is unsupported.** No `lottie` or `rive` package exists and the renderer
   draws bitmaps only. `.webp` (static and animated) and `.png` are accepted.
5. **`legacy_frame_key` is read-only** in the editor — `admin_upsert_frame_v2` has no
   `p_legacy_frame_key` parameter, and no applied migration was edited to add one.
6. **No delete.** Frames are deactivated, never deleted; no delete RPC exists.
7. **`SroodFrame.operator ==` compares `code` only**, so the dialog never relies on `==`
   for change detection.
8. **The DB may still permit `vip_level > 9`** while the client clamps to 1–9 (existing TODO
   at `lib/core/vip/vip_spec.dart:211-213`).
9. **The catalog sync loads from `home_screen.dart`, not `main.dart`** as the plan sketched:
   `get_frame_catalog_v2` is granted to `authenticated` only, so calling it before sign-in
   would always fail.
10. **The editor dialog lives in `lib/features/admin/frames/`**, not
    `lib/features/admin/screens/widgets/` as the plan wrote, keeping the four new frame
    widgets together.
11. **The layout test's stub upload writer returns a bundled-style `assets/…` URL** so the
    widget test never produces a `network` asset — `CachedNetworkImageProvider` needs
    `path_provider`, which is absent under `flutter_test`, and `precacheImage` reports load
    failures to `FlutterError`, which would poison `takeException()`.
12. **SQL was not executed** (see §6).

---

## 9. Manual verification steps

Nothing below has been performed — the app was not run on a device or emulator.

1. **Apply the migration** (with your approval) and confirm the `avatar-frames` bucket
   appears in the Supabase dashboard with a 2 MB limit and the two MIME types.
2. Open **Admin → Gifts & Store → Frame System v2 → Open Frame Management** at **1366×768**
   and **1920×1080**. Confirm no clipped fields, no hidden Save, no overflow stripes.
3. **Create a frame** from name + category + unlock rule + a `.webp` upload. Time it — the
   target is under a minute.
4. Confirm the **live preview shows the uploaded artwork**, not a grey ring, and that the
   animate toggle animates an animated WebP.
5. **Edit one of the 29 existing frames**, change only its name, save, then re-open it and
   confirm `thumbnail_url`, `animation_url`, `unlock_value` and `required_level` are still
   populated. (This is the data-loss regression.)
6. **Duplicate** a frame: confirm the source row is unchanged and that nothing is created
   until you press Save.
7. **Force a code collision** (Advanced → set the code to an existing one): expect a
   readable *"that frame code is already taken"*, **not** a silent overwrite. Verify the
   original row in the DB is untouched.
8. **Upload a 3 MB file**: expect a readable size error, not a raw `StorageException`.
9. **Upload a non-square image**: expect an amber warning that does not block saving.
10. Sign in as a **plain `admin`** and confirm the read-only behaviour described in §8.1 —
    then decide whether to widen the client permission set.
11. Flip `frames_v2_rendering_enabled` to `true` in a **staging** project only, and confirm
    a newly created frame renders on a real profile via the production renderer.

---

## 10. Explicitly not done

No rename or replacement of `frame_catalog`. No duplicate catalog table. No edit to any
applied migration. No change to `frames_v2_user_can_use`, `avatar_frames`, or
`user_avatar_frames`. No reseeding, no legacy ownership migration, no `db reset`, no
migration repair. No service-role credentials in Flutter. No client writes bypassing RLS.
**No git commit, no push, no Supabase remote deploy.** No unrelated feature touched.
