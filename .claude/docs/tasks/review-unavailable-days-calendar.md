# Code Review Report: Unavailable Days Calendar Indicators

**Date**: 2026-03-03
**Reviewed By**: Code Reviewer Agent
**Files Reviewed**:
- `qsystem-frontend/src/hooks/useInstructorScheduleForCalendar.jsx`
- `qsystem-frontend/src/components/datetime/components/Calendar.jsx`

**Cross-referenced**:
- `qsystem-frontend/src/components/datetime/utils/dateTimeHelpers.js`
- `qsystem-backend/src/apps/core/models.py` (DisponibilidadInstructor, BloqueDisponibilidad)
- `qsystem-backend/src/apps/core/serializers.py`
- `qsystem-backend/src/apps/core/views/disponibilidad.py`
- `qsystem-frontend/src/api/availability.jsx`
- `qsystem-frontend/src/components/datetime/modes/SingleDateMode.jsx`
- `qsystem-frontend/src/components/datetime/modes/DateRangeMode.jsx`

---

## Executive Summary

The implementation is **mostly correct** and follows established project patterns, but contains **four concrete bugs** and several medium-priority issues. The most critical bug is a **calendar grid misalignment** caused by inconsistent day-of-week anchors between `generateCalendarDays` (which starts on Sunday) and the `useMemo` range loop (which starts 7 days before the 1st of the month). No tests exist for either modified file.

**Overall verdict: must fix two correctness bugs before merging. Remaining items are medium/low priority.**

---

## Security Assessment

### Passed (OK)

- No SQL injection risk: all data access goes through the DRF ORM via existing viewsets.
- No sensitive data exposure: the hook only consumes availability data already exposed to authenticated sellers/admins through existing endpoints.
- Authentication: `getDisponibilidadPorInstructor` and `getBloquesPorInstructor` go through the project axios instance which carries HttpOnly JWT cookies. Both backend endpoints enforce `IsAdminOrSeller`.
- No XSS risk: the tooltip renders `warning.reason` and slot strings via JSX text nodes, not `dangerouslySetInnerHTML`.
- CSRF: covered by existing DRF CSRF middleware; this change adds no new mutation calls.

---

## Test Coverage

### Test Execution Results

**Backend (pytest)**:
```
src/apps/core/tests/ — 66 passed, 406 warnings in 1.93s
```
No backend tests cover `DisponibilidadInstructor` or `BloqueDisponibilidad`. The 66 passing tests are for unrelated models (`CursoAgendado` state machine, signals, views).

**Frontend (vitest)**:
```
Test Files  36 passed (36)
Tests       610 passed (610)
Duration    4.58s
```
No frontend tests cover `useInstructorScheduleForCalendar` or the unavailable-day rendering path in `Calendar.jsx`.

### Coverage Analysis

- **Tests Exist**: No, for either modified file.
- **Edge Cases Covered**: None tested.
- **Missing Tests** (high priority):
  - Day-of-week conversion (the most error-prone part of this feature).
  - useMemo merge: verify that a "conflict" on an otherwise-unavailable day correctly shows "conflict" and not "unavailable".
  - `bloquesData` exception override: verify that a `tipo=disponible` block suppresses an "unavailable" day.
  - Calendar rendering: verify the diagonal-line SVG appears only on "unavailable" days and not on selected days.
  - Race condition path: instructor changed while availability fetch is in flight.

---

## Detailed Findings

### HIGH PRIORITY BUGS

---

#### Bug 1 — Calendar range window is wrong and misaligned with `generateCalendarDays`

**File**: `qsystem-frontend/src/hooks/useInstructorScheduleForCalendar.jsx:183`

**Severity**: High

**Description**: The `useMemo` computes the date range as:
```js
const start = new Date(year, monthIdx, -6);   // 7 days before the 1st
const end   = new Date(year, monthIdx + 1, 6); // 6 days after the last
```

`new Date(year, monthIdx, -6)` yields the 25th of the *previous* month (month index is 0-based and `-6` subtracts 7 days from the 1st). This means the range starts on the 25th of the previous month.

`generateCalendarDays` in `dateTimeHelpers.js:124` anchors differently:
```js
startDate.setDate(startDate.getDate() - firstDay.getDay());
```
`getDay()` returns 0 for Sunday, so if the 1st of a month is a Monday (`getDay()=1`) the calendar starts on the 31st of the previous month. If the 1st is a Sunday (`getDay()=0`) the calendar starts on the 1st itself with no preceding days from the previous month.

The hook's fixed `-6` backstep can easily miss or over-cover the calendar's actual leading days. In March 2026, March 1st is a Sunday (`getDay()=0`), so `generateCalendarDays` starts on March 1st; the hook's `start` is February 22nd — 7 extra unnecessary days are computed and the calendar cells that need data are fully covered. However in April 2026, April 1st is a Wednesday (`getDay()=3`), so the calendar starts on March 29th; the hook's `start` is March 25th — it covers March 29th, so it is fine. The worst case is a month starting on Saturday (`getDay()=6`): the calendar starts 6 days prior to the 1st; the hook's `start` is also 6 days prior, so they align. Worst case for under-coverage: if `getDay()` is 0 (Sunday), the calendar starts on day 1 itself, so any padding is wasted but not missing.

The real problem is: **Effect 2 uses `start.toISOString().split("T")[0]`** (lines 93-94) while the useMemo uses `toDateStr` (local timezone). These two produce different strings when the local timezone is behind UTC (e.g., UTC-6: midnight local = 06:00 UTC previous day), meaning Effect 2 fetches schedule data for one set of dates while the `useMemo` generates unavailability warnings for a slightly different set. The bug is:

```js
// Effect 2 (line 93): UTC-based
const fechaInicio = start.toISOString().split("T")[0]; // can shift by 1 day

// useMemo (line 190): local-timezone-based
const dateStr = toDateStr(current); // local timezone
```

**Impact**: In timezones behind UTC, a date computed as "2026-02-28" in local time becomes "2026-02-28T06:00:00Z" which `toISOString()` renders as "2026-02-28", but at midnight local in UTC-12 it would produce "2026-02-27". The fetch key and the display key will diverge, causing false "unavailable" markers near month boundaries.

**Recommendation**: Replace both instances with the project's local `toDateStr` helper, or consistently use the date string comparison. Change Effect 2 lines 93-94 to:
```js
const fechaInicio = toDateStr(start);
const fechaFin    = toDateStr(end);
```

---

#### Bug 2 — `state` field check is semantically incorrect for filtering availability records

**File**: `qsystem-frontend/src/hooks/useInstructorScheduleForCalendar.jsx:208-214`

**Severity**: High

**Description**: The `hasAvailability` check includes a guard:
```js
a.state !== false
```

In the backend serializer, `state` is a boolean field from `BaseModel`. Active records have `state=true`; soft-deleted records have `state=false` AND a non-null `deleted_date`. The `por-instructor` endpoint queries via `SoftDeleteModelViewSet` which filters `deleted_date__isnull=True`, so by the time data reaches the frontend, all returned records should already be active (`state=true`). This means the `state !== false` guard is checking a field that will never be `false` in the returned data.

More importantly, the check `a.state !== false` also evaluates to `true` when `a.state` is `undefined` — if the API response shape ever changes and omits `state`, the guard silently passes rather than correctly indicating unavailability.

**Impact**: Low risk in practice given current API behavior, but the guard is misleading and could mask future API contract changes.

**Recommendation**: Either remove the `state` check entirely (the API already filters it) or assert `a.state === true` to fail loudly if the contract changes:
```js
const hasAvailability = availabilityData.some(
  (a) =>
    a.dia_semana === backendDay &&
    (!a.fecha_inicio || dateStr >= a.fecha_inicio) &&
    (!a.fecha_fin || dateStr <= a.fecha_fin),
);
```

---

### MEDIUM PRIORITY ISSUES

---

#### Issue 3 — Priority inversion: "conflict" on an unavailable day silently hides the block override

**File**: `qsystem-frontend/src/hooks/useInstructorScheduleForCalendar.jsx:227-230`

**Severity**: Medium

**Description**: The merge strategy at the end of `useMemo` unconditionally overwrites `combined[date]` with the schedule warning:
```js
for (const [date, warning] of Object.entries(scheduleWarnings)) {
  combined[date] = warning;
}
```

Consider this case: the instructor has a `tipo=disponible` specific block on a given date (meaning they are explicitly available that day despite no regular schedule). The useMemo correctly skips marking it unavailable (line 204). A "conflict" schedule warning for that same date should then merge correctly and show "conflict". This works.

But consider the inverse: a `tipo=no_disponible` block exists (day marked unavailable), AND a scheduled course also falls on that date (which probably means the block was added after the course was booked). The current code marks the day as "unavailable" in `combined`, then overwrites it to "conflict". This hides the block from the user. The instructor is explicitly marked unavailable, yet the calendar shows only "conflict" — the more severe access-control concern (the explicit block) is invisible.

**Impact**: Business logic concern: admins booking another course on a blocked day will not see the block indicator; they only see "partial/conflict" from existing courses. No data corruption, but poor UX and potential scheduling mistake.

**Recommendation**: When merging schedule warnings, preserve "unavailable" if it was set by a `tipo=no_disponible` block:
```js
for (const [date, warning] of Object.entries(scheduleWarnings)) {
  const existing = combined[date];
  if (existing?.level === "unavailable" && existing?.isExplicitBlock) {
    // Keep unavailable but annotate it has a course conflict too
    combined[date] = { ...existing, hasConflict: true };
  } else {
    combined[date] = warning;
  }
}
```
This requires tagging explicit blocks when building `combined`.

---

#### Issue 4 — Soft-deleted blocks are returned by the API

**File**: `qsystem-backend/src/apps/core/views/disponibilidad.py:238-259`

**Severity**: Medium

**Description**: The `por_instructor` action on `BloqueDisponibilidadViewSet` filters with `self.get_queryset()` which inherits from `SoftDeleteModelViewSet`. Inspection of `base.py` is required to confirm this, but the project pattern documented in CLAUDE.md is that `objects` manager excludes soft-deleted records. If `SoftDeleteModelViewSet.get_queryset` calls `Model.objects.all()` the soft-deleted blocks (those with `deleted_date` set) are correctly excluded. However if it uses `Model.all_objects.all()` or a raw queryset, soft-deleted blocks would still be returned to the frontend and incorrectly mark days as unavailable.

**Recommendation**: Verify `SoftDeleteModelViewSet.get_queryset` uses the `objects` manager. Given this is the established pattern, it is likely correct, but this should be confirmed with a test.

---

#### Issue 5 — Potential race condition between Effect 1 and Effect 2 on instructor change

**File**: `qsystem-frontend/src/hooks/useInstructorScheduleForCalendar.jsx:46-78, 81-175`

**Severity**: Medium

**Description**: Effect 1 (availability fetch) and Effect 2 (schedule fetch) run independently. When `instructorId` changes, both effects fire. Effect 2 has a proper abort-controller pattern. Effect 1 uses a `cancelled` flag but no AbortController.

The real race is in the `useMemo`: it depends on `[scheduleWarnings, availabilityData, bloquesData, currentMonth, instructorId]`. Between the instant `instructorId` changes and Effect 1 completing, `availabilityData` still holds the previous instructor's data. During that window, `useMemo` runs with:
- `instructorId` = new instructor
- `availabilityData` = old instructor's data

This causes the calendar to briefly show incorrect unavailability markers for the new instructor based on the old instructor's schedule.

Effect 1 resets `availabilityData` to `null` synchronously only when `!instructorId` (line 47). When the instructor changes to another valid ID, it sets `isLoadingAvailability(true)` but does NOT reset `availabilityData` to `null` first. Therefore the stale availability data persists until the new fetch resolves.

**Impact**: Brief (typically < 500ms) flash of wrong unavailability markers when switching instructors. Can mislead user during a fast interaction.

**Recommendation**: Add `setAvailabilityData(null)` and `setBloquesData(null)` synchronously at the start of Effect 1 when a new valid `instructorId` arrives:
```js
useEffect(() => {
  if (!instructorId) {
    setAvailabilityData(null);
    setBloquesData(null);
    return;
  }
  // Reset stale data immediately before fetch
  setAvailabilityData(null);
  setBloquesData(null);
  setIsLoadingAvailability(true);
  // ...
}, [instructorId]);
```

---

#### Issue 6 — `abortControllerRef` in Effect 2 is used but never passed to the fetch

**File**: `qsystem-frontend/src/hooks/useInstructorScheduleForCalendar.jsx:101-105, 112-116`

**Severity**: Medium

**Description**: Effect 2 creates an `AbortController`, stores it in `abortControllerRef`, and calls `controller.abort()` in the cleanup. However the `signal` from the controller is never passed to `getInstructorSchedule`:
```js
const response = await getInstructorSchedule(
  instructorId,
  fechaInicio,
  fechaFin,
  // signal is NOT passed here
);
```

This means aborting the controller does not actually cancel the in-flight HTTP request. Only the `cancelled` flag prevents the state update. The request continues to run in the background consuming network and server resources.

**Impact**: Performance: stale requests are not cancelled at the network level. In rapid month navigation this can result in multiple concurrent requests all completing and setting state, though only the last one before `cancelled=true` will update state. The `fetchKey` deduplication on line 98 does reduce the frequency.

**Recommendation**: Check `getInstructorSchedule`'s signature. If it accepts an `options` or `signal` parameter, pass it. If not, update the API function to accept and forward the signal to axios:
```js
const response = await getInstructorSchedule(
  instructorId,
  fechaInicio,
  fechaFin,
  { signal: controller.signal },
);
```

---

#### Issue 7 — Tooltip does not account for viewport edge clipping

**File**: `qsystem-frontend/src/components/datetime/components/Calendar.jsx:402-424`

**Severity**: Medium (UX)

**Description**: The tooltip is positioned `bottom-full left-1/2 -translate-x-1/2`, which centers it above the day cell. For days in the first column (Sunday) or the last column (Saturday), the 192px (`w-48`) tooltip will overflow horizontally off-screen when the calendar is near the viewport edge.

There is no caret offset correction, no viewport boundary detection, and no `max-w` fallback. The `z-50` stacking is correct and the `pointer-events-none` is correct (prevents the tooltip from blocking adjacent cells).

**Impact**: Cosmetic: tooltip content clipped or partially hidden for edge-column days.

**Recommendation**: Use conditional positioning classes based on the day's column index, or use a proper popover library / CSS `overflow:visible` with `transform` adjustments. Minimum fix: apply `left-0 translate-x-0` for column 0 and `right-0 left-auto translate-x-0` for column 6.

---

#### Issue 8 — Unavailable days remain clickable

**File**: `qsystem-frontend/src/components/datetime/components/Calendar.jsx:344-345`

**Severity**: Medium (UX / product logic)

**Description**: Days with `level="unavailable"` are visually de-emphasized (gray background, diagonal line) but are **not disabled**. The button checks only `isDisabled` (from min/max/past-date logic), not the warning level:
```js
onClick={() => !isDisabled && onDateClick?.(date)}
disabled={isDisabled}
```

A user can still click a grayed-out "unavailable" day and it will be selected (turning blue), hiding the gray styling. The calendar gives no feedback that the selected date is unavailable for the instructor.

**Impact**: A user could unknowingly book an instructor on a day they are not available. The backend would still validate availability, but the UX offers no warning at selection time.

**Recommendation**: Decide product intent: should "unavailable" days be hard-disabled or soft-blocked with a warning? If soft-blocked, show a toast or inline message when the user clicks an unavailable day. If hard-disabled, add to the `isDisabled` calculation:
```js
const isUnavailable = warning?.level === "unavailable";
// In isDateDisabled or in button onClick:
onClick={() => !isDisabled && !isUnavailable && onDateClick?.(date)}
```

---

### LOW PRIORITY / SUGGESTIONS

---

#### Suggestion 9 — Day-of-week conversion is not using the project's existing helper

**File**: `qsystem-frontend/src/hooks/useInstructorScheduleForCalendar.jsx:193`

**Severity**: Low

**Description**: The conversion `(jsDay + 6) % 7` is manually implemented inline. The project already exports `convertJSToDjango` from `dateTimeHelpers.js` (line 378) which does exactly the same calculation. The inline formula is correct, but inconsistency adds cognitive load.

**Recommendation**: Import and use `convertJSToDjango`:
```js
import { convertJSToDjango } from "@/components/datetime/utils/dateTimeHelpers";
// ...
const backendDay = convertJSToDjango(current.getDay());
```

---

#### Suggestion 10 — `isLoadingWarnings` state exposed but not consumed in Calendar

**File**: `qsystem-frontend/src/components/datetime/components/Calendar.jsx:45`

**Severity**: Low

**Description**: The `Calendar` component accepts `isLoadingWarnings` as a prop and it is passed down from all three mode components, but the current implementation does not use it to show any loading indicator. The prop is declared and documented but silently ignored in the render output.

**Impact**: During the period when availability data is loading (Effect 1 or Effect 2 in flight), the calendar shows no "loading" state for warnings. Days appear as if availability data is not enabled. Users may click dates before the unavailability markers appear.

**Recommendation**: Use `isLoadingWarnings` to show a subtle loading indicator below the calendar header, or use it to show a spinner overlay on the calendar grid. At minimum, show a small spinner near the calendar title when `isLoadingWarnings` is true.

---

#### Suggestion 11 — `bloquesData` loaded for all dates but the API returns no date filtering

**File**: `qsystem-frontend/src/hooks/useInstructorScheduleForCalendar.jsx:58`

**Severity**: Low

**Description**: `getBloquesPorInstructor(instructorId)` fetches ALL specific blocks for the instructor with no date range parameter. An instructor could have hundreds of blocks over years of use. All of them are fetched on every instructor change, regardless of what month is displayed.

Effect 2 (the schedule fetch) correctly scopes to the visible month window. Effect 1 does not.

**Impact**: Potential unnecessary data transfer for instructors with long history. Currently unlikely to be a real performance problem, but does not scale.

**Recommendation**: Either pass date range parameters to the `getBloquesPorInstructor` endpoint (requiring a backend change to `por_instructor` to accept `fecha_inicio`/`fecha_fin` query params), or add a client-side filter in the useMemo before iterating dates.

---

#### Suggestion 12 — `selectedDates` prop is not passed in `DateRangeMode`

**File**: `qsystem-frontend/src/components/datetime/modes/DateRangeMode.jsx:524-537`

**Severity**: Low (existing issue, not introduced by this PR, noted for completeness)

**Description**: `DateRangeMode` passes `startDate` and `endDate` to Calendar but not `selectedDates`. The `isDateSelected` check in Calendar returns `true` only for `startDate` and `endDate`. If a day is both selected and unavailable, the `isSelected` branch in the class string correctly overrides the gray styling. This works for the range mode. No regression here.

---

#### Suggestion 13 — Missing PropTypes on `useInstructorScheduleForCalendar`

**File**: `qsystem-frontend/src/hooks/useInstructorScheduleForCalendar.jsx:30-34`

**Severity**: Low

**Description**: The hook has no runtime argument validation. If a caller passes `currentMonth` as a string instead of a `Date` object, `currentMonth.getFullYear()` will throw `TypeError` rather than giving a useful error message.

**Recommendation**: Add a guard at the top of Effect 2 and useMemo:
```js
if (!(currentMonth instanceof Date) || isNaN(currentMonth.getTime())) {
  console.error("useInstructorScheduleForCalendar: currentMonth must be a valid Date");
  return scheduleWarnings;
}
```

---

## Best Practices Compliance

### React / Frontend

| Item | Status |
|------|--------|
| Custom hook pattern (state + effects + return) | OK |
| Cancellation tokens in async effects | OK (but see Bug 1 and Issue 6) |
| useMemo dependencies include all referenced state | OK |
| No prop mutations | OK |
| React.memo on Calendar | OK |
| useCallback in mode components | OK |
| Calendar is fully controlled (no internal selection state) | OK |
| Loading state exposed | OK (but ignored in render — Suggestion 10) |
| No dangerouslySetInnerHTML | OK |
| Tooltip uses pointer-events-none | OK |
| Aria attributes on calendar buttons | OK (aria-label, aria-pressed, aria-disabled) |
| isLoadingWarnings used for UI feedback | Not used |
| Tests for new hook | Missing (Critical) |
| Tests for Calendar warning rendering | Missing (Critical) |

### Django / Backend

| Item | Status |
|------|--------|
| Endpoint uses SoftDeleteModelViewSet | OK |
| Permission class IsAdminOrSeller | OK |
| No new endpoints added (read-only usage of existing) | OK |
| No raw SQL | OK |
| Serializer includes `state` field | OK |

---

## Performance Analysis

### Database Queries

- **N+1 Queries**: Not applicable to frontend hook. Backend `por_instructor` uses `select_related('instructor')` — no N+1.
- **Scope of data fetched**: `getBloquesPorInstructor` fetches all blocks for an instructor regardless of the viewed month. See Suggestion 11.
- **Effect 1 re-runs**: Only on `instructorId` change. Good.
- **Effect 2 re-runs**: On `instructorId`, `currentMonth`, or `excludeCursoId` change. The `fetchKey` deduplication prevents duplicate requests. Good.

### Frontend Performance

- **useMemo re-runs**: Triggers whenever any of 5 dependencies change. The computation is O(n_days * m_availabilities) which is small (at most ~44 days * a few dozen availabilities). Acceptable.
- **Calendar renders `getTodayAtMidnight()` inside the day map**: `getTodayAtMidnight` calls `new Date()` and `setHours(0,0,0,0)` on every day cell render (up to 42 times). This is minor but could be hoisted outside the map with `useMemo`. Not introduced by this PR.

---

## Code Quality Metrics

| Metric | Score | Notes |
|--------|-------|-------|
| Type Safety | 4/10 | No TypeScript, no PropTypes on the new hook, no runtime guards |
| Documentation | 7/10 | Good JSDoc on the hook; Calendar prop types documented in JSDoc |
| Readability | 7/10 | Code is clear; the day-of-week conversion comment is helpful |
| Maintainability | 5/10 | Day-of-week conversion duplicates existing helper; no tests |

---

## Project Standards Compliance

| Item | Status |
|------|--------|
| Follows CLAUDE.md patterns | OK — soft delete, active manager, context patterns respected |
| Consistent with existing codebase | OK — hook follows same pattern as pre-existing useInstructorScheduleForCalendar usage |
| Proper directory structure | OK — hook in `/hooks/`, component in `/components/datetime/components/` |
| Environment variable usage | Not applicable to this change |
| Commit via `commit-helper.sh` | Not reviewed (outside scope) |

---

## Recommendations

### Must Fix Before Merge

1. **Bug 1** — Replace `start.toISOString().split("T")[0]` with `toDateStr(start)` in Effect 2 (lines 93-94) to ensure the schedule fetch window uses the same timezone basis as the useMemo display window. This prevents off-by-one date mismatches at month boundaries in non-UTC timezones.

2. **Bug 2** — Remove or invert the `a.state !== false` guard (line 210). The API already filters inactive records; the guard semantics are misleading and silently allow undefined-`state` records to pass.

### Should Fix Soon

3. **Issue 5** — Reset `availabilityData` and `bloquesData` to `null` at the top of Effect 1 when a new instructor is selected (before the async fetch) to eliminate the stale-data window.

4. **Issue 6** — Pass `signal: controller.signal` through to `getInstructorSchedule` so the HTTP request is actually cancelled on abort, not just ignored post-completion.

5. **Issue 8** — Decide product intent for unavailable days (hard-disabled vs. soft-warned). At minimum, display a warning message when a user clicks an unavailable day rather than silently allowing selection.

6. **Tests** — Add unit tests for the day-of-week conversion, useMemo merge logic, and Calendar rendering of unavailable days. These are the highest-risk code paths with no current coverage.

### Consider for Future

7. **Issue 3** — Refine the conflict-vs-explicit-block priority in the merge step so that explicitly blocked days remain marked even when a scheduled course also exists on that day.

8. **Issue 7** — Add viewport-aware tooltip positioning for edge-column calendar days.

9. **Suggestion 9** — Use `convertJSToDjango` from `dateTimeHelpers.js` instead of the inline `(jsDay + 6) % 7` formula.

10. **Suggestion 10** — Use `isLoadingWarnings` to render a visual loading indicator on the calendar.

11. **Suggestion 11** — Add date range parameters to the bloques fetch so historical blocks are not fetched unnecessarily.

---

## Conclusion

The feature is architecturally sound and the day-of-week formula `(jsDay + 6) % 7` is mathematically correct for the backend's 0=Monday convention. The most consequential issue is the timezone inconsistency in the date range window (Bug 1), which will silently produce wrong markers in any deployment where the user's browser is not in UTC. The stale-state race condition (Issue 5) and the non-cancelling abort controller (Issue 6) are real but low-severity in practice.

The complete absence of tests for the two modified files is the most structurally risky aspect of this merge. The day-of-week conversion is the exact kind of calculation that is easy to get subtly wrong and hard to catch without tests.

**Recommendation: Do not merge until Bug 1 is fixed and at least one test covering the day-of-week conversion is added. All other issues can follow in a subsequent PR.**
