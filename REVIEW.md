# Code Review — Fresher Fixes

> **Reviewer:** Senior Dev
> **Date:** 24/03/2026
> **Status:** Needs revision — fix the items below then ping me for re-review.

---

## 🔴 Bug Fix

### 1. `getUpcomingSessions()` / `getPastSessions()` — Use `targetWeekStart` (+ 1 week)

**Problem:** `seminarDate` defaults to `0` when the team hasn't set it yet. This causes completed sessions with no date to always show as "past." These sessions should show as "upcoming" until the entire presentation week has finished.

**Fix:** Use `targetWeekStart + 7 days` to ensure they stay in "Upcoming" until the target week is over.

```diff
 // getUpcomingSessions
-(s == SessionStatus.COMPLETED &&
-    sessions[sessionList[i]].seminarDate >= block.timestamp)
+(s == SessionStatus.COMPLETED &&
+    sessions[sessionList[i]].targetWeekStart + 7 days >= block.timestamp)

 // getPastSessions
-(s == SessionStatus.COMPLETED &&
-    sessions[sessionList[i]].seminarDate < block.timestamp)
+(s == SessionStatus.COMPLETED &&
+    sessions[sessionList[i]].targetWeekStart + 7 days < block.timestamp)
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
Current implementation is **hardcoded to 1 Fulltime + 3 Interns (4 rounds)**:a

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

### 9. 🟡 Automation — DERIVE `targetWeekStart` automatically

**Problem:**
The admin currently passes a manual `targetWeekStart` timestamp. This is error-prone. Since we have `defaultPreparationWeeks` (4 weeks by default), the contract should calculate this itself to make the `preparationWeeks` config useful.

---

**Fix:**

1.  **Remove the parameter** from `createRaceSession()`.
2.  **Calculate the timestamp** inside: `target = block.timestamp + (preparationWeeks * 1 weeks)`.
3.  **Round to Monday** using a helper function to ensure consistency.

```solidity
function createRaceSession() external onlyAdmin returns (uint256 sessionId) {
    uint256 targetTimestamp = block.timestamp + (defaultPreparationWeeks * 1 weeks);
    uint256 monday = _getMonday(targetTimestamp);
    
    // ... use monday as targetWeekStart
}

function _getMonday(uint256 t) internal pure returns (uint256) {
    // Helper logic to return the start of the week (Monday 00:00)
}
```


---