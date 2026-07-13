# Phase 4 Lint Report

`supabase db lint --linked --fail-on error` failed on pre-existing live functions.
Findings include ambiguous `admin_record_audit` overloads, missing report/game
columns, unresolved crypto helpers and the VIP alias-column defect. These are
existing legacy issues; the VIP issue is a production blocker addressed by an
unapplied forward-only Phase 4 migration.

`supabase db lint --local` could not run because Docker/Postgres is unavailable.
Phase 3/4 migration-introduced lint findings cannot yet be classified by execution.
Flutter analysis and repository whitespace validation are recorded separately.

- `flutter analyze`: passed, no issues (43.4s).
- Relevant Agency Flutter tests: 5 passed, 0 failed.
- `git diff --check` on Phase 3/4 Agency files: passed.
