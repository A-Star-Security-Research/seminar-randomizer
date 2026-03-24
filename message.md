# Code Review — Fresher Fixes

> **Reviewer:** Senior Dev
> **Date:** 24/03/2026
> **Status:** Needs revision — fix the items below then ping me for re-review.

---

## 🔴 Bug Fix

### 1. `getUpcomingSessions()` / `getPastSessions()` — Use `targetWeekStart` instead of `seminarDate`

**Problem:** `seminarDate` defaults to `0` when the team hasn't set it yet. This causes:
- COMPLETED sessions with no date → `seminarDate(0) < block.timestamp` → always shows as "past" even when it's upcoming.
- These sessions disappear from `getUpcomingSessions()`.

**Fix:** Replace `seminarDate` with `targetWeekStart` in both functions. `targetWeekStart` is always set at creation time → reliable.

```diff# Code Review — Fresher Fixes

> **Reviewer:** Senior Dev
> **Date:** 24/03/2026
> **Status:** Needs revision — fix the items below then ping me for re-review.

---

## 🔴 Bug Fix

### 1. `getUpcomingSessions()` / `getPastSessions()` — Use `targetWeekStart` instead of `seminarDate`

**Problem:** `seminarDate` defaults to `0` when the team hasn't set it yet. This causes:
- COMPLETED sessions with no date → `seminarDate(0) < block.timestamp` → always shows as "past" even when it's upcoming.
- These sessions disappear from `getUpcomingSessions()`.

**Fix:** Replace `seminarDate` with `targetWeekStart` in both functions. `targetWeekStart` is always set at creation time → reliable.

```diff
 // getUpcomingSessions
-(s == SessionStatus.COMPLETED &&
-    sessions[sessionList[i]].seminarDate >= block.timestamp)
+(s == SessionStatus.COMPLETED &&
+    sessions[sessionList[i]].targetWeekStart >= block.timestamp)

 // getPastSessions
-(s == SessionStatus.COMPLETED &&
-    sessions[sessionList[i]].seminarDate < block.timestamp)
+(s == SessionStatus.COMPLETED &&
+    sessions[sessionList[i]].targetWeekStart < block.timestamp)
```

### 2. `getUpcomingSessions()` — Include PAUSED sessions

**Problem:** PAUSED sessions are invisible — excluded from both upcoming and past. They should show in upcoming.

**Fix:**

```diff
 if (
     s == SessionStatus.RACING ||
     s == SessionStatus.PENDING ||
+    s == SessionStatus.PAUSED ||
     (s == SessionStatus.COMPLETED &&
-        sessions[sessionList[i]].seminarDate >= block.timestamp)
+        sessions[sessionList[i]].targetWeekStart >= block.timestamp)
 )
```

Apply this change in **both** the counting loop and the filling loop inside `getUpcomingSessions()`.

---

## 🟡 Clean Up

### 3. Remove unused `TEAM_MEMBER` constant

`bytes32 public constant TEAM_MEMBER = keccak256("TEAM_MEMBER")` on line 9 is declared but never used. Your `_isTeamMemberOrAdmin()` function already handles team member checks dynamically (which is correct). Delete the dead code.

```diff
 bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
-bytes32 public constant TEAM_MEMBER = keccak256("TEAM_MEMBER");
```

---

## 🟡 Missing Tests

### 4. Add tests for SpeakerManager and SeminarManager

Currently only `SeminarRandomizer` has tests. Add test files:

- `test/SpeakerManager.ts` — test add/update/remove speaker, addSeminarToSpeaker, view functions.
- `test/SeminarManager.ts` — test create seminar, update info, update slide link, view functions.

### 5. Add tests for edge cases in SeminarRandomizer

Current tests cover the happy path. Add tests for:
- `pauseSession()` and `resumeSession()` — verify status transitions.
- `cancelSession()` — verify cooldown reset.
- `updateSeminarInfo()` / `updateSeminarDate()` — verify team member access and non-member rejection.
- Racing when pool size is exactly the minimum (1 fulltime, 3 interns).

---

## 🟢 Nice to Have

### 6. Add NatSpec comments to contract functions

Most functions have no `@notice`, `@param`, or `@return` documentation. Add NatSpec for all public/external functions so the ABI generates readable docs.


# 🟡 Design Improvements

### 7. Make team composition configurable (Intern / Fulltime count)

**Problem:**
Current implementation is **hardcoded to 1 Fulltime + 3 Interns (4 rounds)**:

* `currentRound == 1` → fulltime
* `currentRound == 2-4` → intern
* Completion condition tied to `round == 4`

This makes the system **not flexible** if requirements change (e.g. 2 mentors + 2 interns).

---

**Fix:**
Move from **round-based logic → count-based logic**

#### Step 1 — Add config to `RaceSession`

```solidity
uint256 requiredInterns;
uint256 requiredFulltimes;
```

---

#### Step 2 — Track selections dynamically

```solidity
address[] selectedFulltimes; // instead of single selectedMentor
address[] selectedInterns;
```

---

#### Step 3 — Replace round logic

```diff
- if (currentRound == 1) → fulltime
- else → intern
+ if (selectedFulltimes.length < requiredFulltimes)
+     pick from fulltimePool;
+ else
+     pick from internPool;
```

---

#### Step 4 — Replace completion condition

```diff
- if (currentRound == 4)
+ if (
+     selectedFulltimes.length == requiredFulltimes &&
+     selectedInterns.length == requiredInterns
+ )
```

---

**Result:**

* Supports flexible configurations:

  * 1 mentor + 3 interns (current)
  * 2 mentors + 2 interns
  * 1 mentor + 2 interns
* No change needed in randomness logic

---

### 8. Improve randomness using rolling seed (reduce correlation)

**Problem:**
Current randomness:

```solidity
keccak256(prevrandao, timestamp, sessionId, currentRound)
```

All rounds share the same:

* `block.prevrandao`
* `block.timestamp`

👉 This makes outputs **different but still correlated** (same base entropy).

---

**Fix:**
Use a **rolling (chained) seed** so each round depends on the previous one.

---

#### Step 1 — Add session seed

```solidity
bytes32 public sessionSeed;
```

Initialize when creating session:

```solidity
sessionSeed = keccak256(
    abi.encodePacked(block.prevrandao, sessionId)
);
```

---

#### Step 2 — Update seed every round

```solidity
sessionSeed = keccak256(
    abi.encodePacked(sessionSeed, currentRound)
);

uint256 randomIndex = uint256(sessionSeed) % pool.length;
```

---
 // getUpcomingSessions
-(s == SessionStatus.COMPLETED &&
-    sessions[sessionList[i]].seminarDate >= block.timestamp)
+(s == SessionStatus.COMPLETED &&
+    sessions[sessionList[i]].targetWeekStart >= block.timestamp)

 // getPastSessions
-(s == SessionStatus.COMPLETED &&
-    sessions[sessionList[i]].seminarDate < block.timestamp)
+(s == SessionStatus.COMPLETED &&
+    sessions[sessionList[i]].targetWeekStart < block.timestamp)
```

### 2. `getUpcomingSessions()` — Include PAUSED sessions

**Problem:** PAUSED sessions are invisible — excluded from both upcoming and past. They should show in upcoming.

**Fix:**

```diff
 if (
     s == SessionStatus.RACING ||
     s == SessionStatus.PENDING ||
+    s == SessionStatus.PAUSED ||
     (s == SessionStatus.COMPLETED &&
-        sessions[sessionList[i]].seminarDate >= block.timestamp)
+        sessions[sessionList[i]].targetWeekStart >= block.timestamp)
 )
```

Apply this change in **both** the counting loop and the filling loop inside `getUpcomingSessions()`.

---

## 🟡 Clean Up

### 3. Remove unused `TEAM_MEMBER` constant

`bytes32 public constant TEAM_MEMBER = keccak256("TEAM_MEMBER")` on line 9 is declared but never used. Your `_isTeamMemberOrAdmin()` function already handles team member checks dynamically (which is correct). Delete the dead code.

```diff
 bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
-bytes32 public constant TEAM_MEMBER = keccak256("TEAM_MEMBER");
```

---

## 🟡 Missing Tests

### 4. Add tests for SpeakerManager and SeminarManager

Currently only `SeminarRandomizer` has tests. Add test files:

- `test/SpeakerManager.ts` — test add/update/remove speaker, addSeminarToSpeaker, view functions.
- `test/SeminarManager.ts` — test create seminar, update info, update slide link, view functions.

### 5. Add tests for edge cases in SeminarRandomizer

Current tests cover the happy path. Add tests for:
- `pauseSession()` and `resumeSession()` — verify status transitions.
- `cancelSession()` — verify cooldown reset.
- `updateSeminarInfo()` / `updateSeminarDate()` — verify team member access and non-member rejection.
- Racing when pool size is exactly the minimum (1 fulltime, 3 interns).

---

## 🟢 Nice to Have

### 6. Add NatSpec comments to contract functions

Most functions have no `@notice`, `@param`, or `@return` documentation. Add NatSpec for all public/external functions so the ABI generates readable docs.


# 🟡 Design Improvements

### 7. Make team composition configurable (Intern / Fulltime count)

**Problem:**
Current implementation is **hardcoded to 1 Fulltime + 3 Interns (4 rounds)**:

* `currentRound == 1` → fulltime
* `currentRound == 2-4` → intern
* Completion condition tied to `round == 4`

This makes the system **not flexible** if requirements change (e.g. 2 mentors + 2 interns).

---

**Fix:**
Move from **round-based logic → count-based logic**

#### Step 1 — Add config to `RaceSession`

```solidity
uint256 requiredInterns;
uint256 requiredFulltimes;
```

---

#### Step 2 — Track selections dynamically

```solidity
address[] selectedFulltimes; // instead of single selectedMentor
address[] selectedInterns;
```

---

#### Step 3 — Replace round logic

```diff
- if (currentRound == 1) → fulltime
- else → intern
+ if (selectedFulltimes.length < requiredFulltimes)
+     pick from fulltimePool;
+ else
+     pick from internPool;
```

---

#### Step 4 — Replace completion condition

```diff
- if (currentRound == 4)
+ if (
+     selectedFulltimes.length == requiredFulltimes &&
+     selectedInterns.length == requiredInterns
+ )
```

---

**Result:**

* Supports flexible configurations:

  * 1 mentor + 3 interns (current)
  * 2 mentors + 2 interns
  * 1 mentor + 2 interns
* No change needed in randomness logic

---

### 8. Improve randomness using rolling seed (reduce correlation)

**Problem:**
Current randomness:

```solidity
keccak256(prevrandao, timestamp, sessionId, currentRound)
```

All rounds share the same:

* `block.prevrandao`
* `block.timestamp`

👉 This makes outputs **different but still correlated** (same base entropy).

---

**Fix:**
Use a **rolling (chained) seed** so each round depends on the previous one.

---

#### Step 1 — Add session seed

```solidity
bytes32 public sessionSeed;
```

Initialize when creating session:

```solidity
sessionSeed = keccak256(
    abi.encodePacked(block.prevrandao, sessionId)
);
```

---

#### Step 2 — Update seed every round

```solidity
sessionSeed = keccak256(
    abi.encodePacked(sessionSeed, currentRound)
);

uint256 randomIndex = uint256(sessionSeed) % pool.length;
```

---