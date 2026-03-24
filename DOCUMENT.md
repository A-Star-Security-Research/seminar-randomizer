# Contract Specification

# Seminar Randomizer — Smart Contract Spec

> **Assignee:** Tuan
**Scope:** Smart contract development only (Solidity).
**Stack:** Solidity , Hardhat, OpenZeppelin Upgradeable
> 

---

## 1. Tổng quan

Hệ thống gồm 3 contracts cần triển khai:

| Contract | Mô tả |
| --- | --- |
| `SpeakerManager.sol` | Quản lý thông tin speakers (tên, address, lịch sử seminar) |
| `SeminarManager.sol` | Quản lý thông tin seminar (title, description, speakers, slide link) |
| `SeminarRandomizer.sol` | Random on-chain để chọn nhóm trình bày seminar |

> **Lưu ý:** `SpeakerManager` và `SeminarManager` sẽ được dùng lại cho hệ thống Voting sau này.
> 

---

## 2. SpeakerManager.sol

### Mô tả

Quản lý profile của các speakers trong tổ chức.

### Data Structures

```solidity
struct Speaker {
    string name;
    address speakerAddress;
    uint256[] seminarIds;       // Danh sách seminar đã trình bày
}

mapping(address => Speaker) public speakers;
address[] public speakerList;
```

### Functions

```solidity
// === Admin Functions ===
function addSpeaker(address _speaker, string memory _name) external onlyAdmin;
function updateSpeaker(address _speaker, string memory _name) external onlyAdmin;
function removeSpeaker(address _speaker) external onlyAdmin;
function addSeminarToSpeaker(address _speaker, uint256 _seminarId) external onlyAdmin;

// === View Functions ===
function getSpeaker(address _speaker) external view returns (Speaker memory);
function getAllSpeakers() external view returns (address[] memory);
function getSpeakerSeminars(address _speaker) external view returns (uint256[] memory);
```

### Events

```solidity
event SpeakerAdded(address indexed speaker, string name);
event SpeakerUpdated(address indexed speaker, string name);
event SpeakerRemoved(address indexed speaker);
```

---

## 3. SeminarManager.sol

### Mô tả

Quản lý thông tin của các buổi seminar.

### Data Structures

```solidity
struct Seminar {
    uint256 id;
    string title;
    string description;
    string slideLink;           // Link Drive/Slide
    address[] speakers;
    uint256 createdAt;
}

mapping(uint256 => Seminar) public seminars;
uint256 public nextSeminarId;
```

### Functions

```solidity
// === Admin Functions ===
function createSeminar(
    string memory _title,
    string memory _description,
    string memory _slideLink,
    address[] memory _speakers
) external onlyAdmin returns (uint256 seminarId);

function updateSeminarInfo(uint256 _seminarId, string memory _title, string memory _description) external onlyAdmin;
function updateSlideLink(uint256 _seminarId, string memory _slideLink) external onlyAdmin;

// === View Functions ===
function getSeminar(uint256 _seminarId) external view returns (Seminar memory);
function getAllSeminars() external view returns (uint256[] memory);
```

### Events

```solidity
event SeminarCreated(uint256 indexed seminarId, string title, address[] speakers);
event SeminarUpdated(uint256 indexed seminarId, string title);
event SlideLinkUpdated(uint256 indexed seminarId, string slideLink);
```

---

## 4. SeminarRandomizer.sol — Contract chính

### 4.1 Bối cảnh

Mỗi tuần, 1 nhóm tổ chức seminar. Cuối buổi, ta **random** để chọn nhóm trình bày cho tuần tương lai.

**Cấu trúc nhóm:** 3 Interns + 1 Fulltime (mentor). Hai pool **riêng biệt**.

**Quy trình random:**
1. Random từ pool **Fulltime** → chọn 1 mentor.
2. Random từ pool **Intern** → chọn intern #1, loại khỏi pool.
3. Random từ pool **Intern còn lại** → chọn intern #2, loại khỏi pool.
4. Random từ pool **Intern còn lại** → chọn intern #3.
- **Tổng: 4 lần random**, kết quả cuối = 1 nhóm hoàn chỉnh.

### 4.2 Data Structures

```solidity
enum ParticipantType { INTERN, FULLTIME }
enum SessionStatus { PENDING, RACING, COMPLETED, PAUSED, CANCELLED }

struct RaceSession {
    uint256 sessionId;
    SessionStatus status;
    uint256 createdAt;

    // ── Scheduling ──
    uint256 targetWeekStart;        // Timestamp ngày đầu tuần mục tiêu
    uint256 preparationWeeks;       // Số tuần chuẩn bị (mặc định 4, có thể thay đổi)

    // ── Pools cho session này (snapshot từ global pool) ──
    address[] internPool;
    address[] fulltimePool;

    // ── Kết quả random ──
    address selectedMentor;
    address[] selectedInterns;      // Push lần lượt qua 3 rounds

    uint256 currentRound;           // 0: chưa bắt đầu, 1: random fulltime, 2-4: random intern

    // ── Seminar info (cập nhật sau khi được chọn) ──
    string seminarTitle;            // Nhóm tự update sau
    string seminarDescription;      // Nhóm tự update sau
    uint256 seminarDate;            // Nhóm tự chọn ngày trong tuần target
}

// ── Global Pools ──
address[] public globalInternPool;
address[] public globalFulltimePool;
mapping(address => string) public participantNames;
mapping(address => ParticipantType) public participantTypes;

// ── Cooldown: ngăn chọn 2 tuần liên tiếp ──
mapping(address => uint256) public lastChosenWeek;
// Khi participant được chọn cho targetWeekStart X, set lastChosenWeek[participant] = X
// Khi tạo session mới cho targetWeekStart Y, loại participant có lastChosenWeek == Y - 1 tuần

// ── Config ──
uint256 public defaultPreparationWeeks;  // Mặc định = 4
```

### 4.3 Admin Functions — Pool Management

```solidity
/// @notice Thêm participant vào global pool
function addParticipant(
    address _participant,
    string memory _name,
    ParticipantType _pType
) external onlyAdmin;

/// @notice Xóa participant khỏi global pool
function removeParticipant(address _participant) external onlyAdmin;

/// @notice Cập nhật danh sách intern pool (ghi đè toàn bộ)
function updateInternPool(address[] memory _newPool) external onlyAdmin;

/// @notice Cập nhật danh sách fulltime pool (ghi đè toàn bộ)
function updateFulltimePool(address[] memory _newPool) external onlyAdmin;

/// @notice Lấy danh sách participants theo type
function getParticipants(ParticipantType _pType) external view returns (address[] memory);
```

### 4.4 Admin Functions — Session Management

```solidity
/// @notice Tạo race session mới
/// @dev Copy global pool vào session, loại những ai có lastChosenWeek == targetWeekStart - 1 tuần
function createRaceSession(uint256 targetWeekStart) external onlyAdmin returns (uint256 sessionId);

/// @notice Cập nhật số tuần chuẩn bị cho 1 session
function updatePreparationWeeks(uint256 sessionId, uint256 _weeks) external onlyAdmin;

/// @notice Cập nhật số tuần chuẩn bị mặc định (cho sessions tương lai)
function setDefaultPreparationWeeks(uint256 _weeks) external onlyAdmin;

/// @notice Pause session (hoãn seminar)
function pauseSession(uint256 sessionId) external onlyAdmin;

/// @notice Resume session đã pause
function resumeSession(uint256 sessionId) external onlyAdmin;

/// @notice Cancel session hoàn toàn
function cancelSession(uint256 sessionId) external onlyAdmin;
```

### 4.5 Race Functions — Randomization

```solidity
/// @notice Bắt đầu round tiếp theo: random 1 người từ pool tương ứng
/// @dev Round 1: random từ fulltimePool. Round 2-4: random từ internPool.
/// @dev Kết quả trả về ngay trong cùng transaction — 1 click, xong.
function startNextRace(uint256 sessionId) external onlyAdmin;
```

**Logic bên trong `startNextRace`:**
1. Require `status == RACING || status == PENDING` (nếu PENDING thì chuyển sang RACING).
2. `currentRound++`.
3. Xác định pool: round 1 = `fulltimePool`, round 2-4 = `internPool`.
4. Random: `uint256 randomIndex = uint256(keccak256(abi.encodePacked(block.prevrandao, block.timestamp, sessionId, currentRound))) % pool.length`
5. Chọn winner = `pool[randomIndex]`.
6. Nếu intern: swap-and-pop khỏi `internPool` trong session.
7. Nếu round == 4: set `status = COMPLETED`, set `lastChosenWeek[participant]` cho tất cả 4 người.
8. Emit event `RaceResult`.

---

### 4.6 Randomization — `block.prevrandao`

Vì đây là contract nội bộ cho team (không có betting, không cần chống gian lận), ta dùng **`block.prevrandao`** — cách đơn giản nhất.

| Đặc điểm | Chi tiết |
| --- | --- |
| **Chi phí** | Chỉ tốn gas thường (rẻ nhất có thể) |
| **Số transaction** | 1 transaction duy nhất — gọi `startNextRace()`, kết quả trả về ngay |
| **Setup** | Không cần gì thêm — không LINK token, không subscription, không commit/reveal |
| **Độ tin cậy** | Đủ tốt cho mục đích nội bộ. Validator có thể influence nhưng không ai có lý do làm vậy |

```solidity
/// @dev Random từ prevrandao — kết hợp nhiều nguồn entropy để tránh trùng giữa các round
function _getRandomIndex(
    uint256 sessionId,
    uint256 round,
    uint256 poolLength
) internal view returns (uint256) {
    return uint256(
        keccak256(
            abi.encodePacked(
                block.prevrandao,
                block.timestamp,
                sessionId,
                round
            )
        )
    ) % poolLength;
}
```

> **Tại sao kết hợp nhiều giá trị trong keccak256?**
- `block.prevrandao`: Nguồn random chính từ beacon chain.
- `block.timestamp`: Thêm entropy.
- `sessionId` + `round`: Đảm bảo mỗi round trong mỗi session cho ra số khác nhau, ngay cả khi cùng block.
> 

---

### 4.7 Seminar Info Functions

Nhóm được chọn **chưa có** thông tin seminar ngay. Họ tự cập nhật bất kỳ lúc nào.

```solidity
/// @notice Cập nhật tiêu đề và mô tả seminar
/// @dev Ai trong nhóm (selectedMentor hoặc selectedInterns) đều có thể gọi, hoặc chỉ admin
function updateSeminarInfo(
    uint256 sessionId,
    string memory _title,
    string memory _description
) external;

/// @notice Cập nhật ngày trình bày (phải nằm trong tuần target)
function updateSeminarDate(uint256 sessionId, uint256 _date) external;
```

### 4.8 Cooldown Logic (Không chọn 2 tuần liên tiếp)

```solidity
/// @dev Khi tạo session, lọc pool:
function _filterCooldownParticipants(
    address[] memory pool,
    uint256 targetWeekStart
) internal view returns (address[] memory filtered) {
    // Loại participant nếu lastChosenWeek[participant] == targetWeekStart - 1 tuần
    // Tức là nếu họ đã được chọn cho tuần ngay trước tuần target → skip
}
```

**Ví dụ:**
- Tom được chọn cho tuần 10.
- Tạo session cho tuần 11 → Tom bị loại khỏi pool.
- Tạo session cho tuần 12 → Tom được tham gia lại bình thường.

### 4.9 Pause/Delay Logic

```solidity
/// @notice Pause: Hoãn seminar vì lý do bận
function pauseSession(uint256 sessionId) external onlyAdmin {
    require(status == SessionStatus.RACING || status == SessionStatus.COMPLETED);
    session.status = SessionStatus.PAUSED;
    emit SessionPaused(sessionId);
}

/// @notice Resume: Tiếp tục session đã pause
function resumeSession(uint256 sessionId) external onlyAdmin {
    require(session.status == SessionStatus.PAUSED);
    // Khôi phục status trước đó (RACING nếu chưa random xong, COMPLETED nếu đã xong)
    emit SessionResumed(sessionId);
}

/// @notice Cancel: Hủy session hoàn toàn, reset cooldown cho nhóm đã chọn
function cancelSession(uint256 sessionId) external onlyAdmin {
    // Reset lastChosenWeek cho các participant đã chọn
    // Set status = CANCELLED
    emit SessionCancelled(sessionId);
}
```

---

## 5. View / Query Functions

```solidity
/// @notice Lấy thông tin session
function getSession(uint256 sessionId) external view returns (RaceSession memory);

/// @notice Lấy nhóm đã chọn
function getSelectedTeam(uint256 sessionId) external view
    returns (address mentor, address[] memory interns);

/// @notice Lấy sessions sắp tới (COMPLETED nhưng chưa đến ngày seminar, hoặc RACING)
function getUpcomingSessions() external view returns (uint256[] memory);

/// @notice Lấy sessions đã diễn ra
function getPastSessions() external view returns (uint256[] memory);

/// @notice Lấy intern pool còn lại trong session (cho UI duck race animation)
function getRemainingInternPool(uint256 sessionId) external view returns (address[] memory);

/// @notice Lấy fulltime pool trong session
function getFulltimePool(uint256 sessionId) external view returns (address[] memory);

/// @notice Kiểm tra participant có bị cooldown không cho tuần cụ thể
function isOnCooldown(address participant, uint256 targetWeekStart) external view returns (bool);

/// @notice Lấy tất cả sessions
function getAllSessions() external view returns (uint256[] memory);
```

---

## 6. Events

```solidity
// ── Session ──
event RaceSessionCreated(uint256 indexed sessionId, uint256 targetWeekStart, uint256 prepWeeks);
event SessionPaused(uint256 indexed sessionId);
event SessionResumed(uint256 indexed sessionId);
event SessionCancelled(uint256 indexed sessionId);

// ── Race ──
event RaceResult(uint256 indexed sessionId, uint256 round, address indexed winner, ParticipantType pType);
event SessionCompleted(uint256 indexed sessionId, address mentor, address[] interns);

// ── Seminar Info ──
event SeminarInfoUpdated(uint256 indexed sessionId, string title, string description);
event SeminarDateUpdated(uint256 indexed sessionId, uint256 date);
event PreparationWeeksUpdated(uint256 indexed sessionId, uint256 weeks);

// ── Pool ──
event ParticipantAdded(address indexed participant, string name, ParticipantType pType);
event ParticipantRemoved(address indexed participant);
event InternPoolUpdated(uint256 count);
event FulltimePoolUpdated(uint256 count);
```

---

## 7. Access Control

Dùng OpenZeppelin `AccessControlUpgradeable`:

| Role | Quyền |
| --- | --- |
| `ADMIN_ROLE` | Tạo session, trigger race, manage pools, pause/cancel |
| `TEAM_MEMBER` | Update seminar info/date cho session mà mình thuộc nhóm |
| Public | View functions |

---

## 8. Race Flow tổng thể

```
Admin tạo Session (createRaceSession)
    → Copy global pool, lọc cooldown
    → status = PENDING
    │
    ├─ Round 1: startNextRace() → chọn 1 Fulltime (kết quả ngay)
    │   status = RACING
    │
    ├─ Round 2: startNextRace() → chọn Intern #1, loại khỏi pool
    │
    ├─ Round 3: startNextRace() → chọn Intern #2, loại khỏi pool
    │
    └─ Round 4: startNextRace() → chọn Intern #3
        status = COMPLETED
        Set lastChosenWeek cho 4 người
        emit SessionCompleted

    ─── Sau đó ───
    Nhóm update seminarTitle, seminarDescription, seminarDate bất kỳ lúc nào.
    Admin có thể pauseSession() nếu bận, hoặc cancelSession() nếu cần hủy.
```

**Admin chỉ cần gọi `startNextRace()` 4 lần.** Mỗi lần = 1 transaction, kết quả trả về ngay. Không cần gọi thêm hàm nào khác.

---

## 9. Notes

1. **Tất cả contracts phải Upgradeable** — dùng `Initializable`, `AccessControlUpgradeable`, KHÔNG dùng `constructor`.
2. **`block.prevrandao`** — chỉ available trên post-merge chains (Sepolia, BSC Testnet đều hỗ trợ). Trên Hardhat local, dùng `hardhat_setPrevRandao` để mock giá trị random khi test.
3. **Swap-and-pop:** Khi loại intern khỏi pool, swap vị trí với phần tử cuối rồi pop. Tiết kiệm gas.
4. **Cooldown dùng timestamp tuần** — quy ước: `targetWeekStart` luôn là timestamp 00:00 UTC ngày thứ Hai của tuần đó. Helper function `getWeekStart(uint256 timestamp)` rất hữu ích.
5. **Test trên Hardhat local trước** — Sau đó deploy testnet (Sepolia hoặc BSC Testnet).
6. **Gas:** Chỉ random + CRUD. Không lo gas.