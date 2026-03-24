// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract SeminarRandomizer is Initializable, AccessControlUpgradeable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TEAM_MEMBER = keccak256("TEAM_MEMBER");

    enum ParticipantType {
        INTERN,
        FULLTIME
    }
    enum SessionStatus {
        PENDING,
        RACING,
        COMPLETED,
        PAUSED,
        CANCELLED
    }

    struct RaceSession {
        uint256 sessionId;
        SessionStatus status;
        uint256 createdAt;
        uint256 targetWeekStart;
        uint256 preparationWeeks;
        address[] internPool;
        address[] fulltimePool;
        address selectedMentor;
        address[] selectedInterns;
        uint256 currentRound;
        string seminarTitle;
        string seminarDescription;
        uint256 seminarDate;
    }

    mapping(uint256 => RaceSession) public sessions;
    uint256 public nextSessionId;
    uint256[] public sessionList;

    address[] public globalInternPool;
    address[] public globalFulltimePool;
    mapping(address => string) public participantNames;
    mapping(address => ParticipantType) public participantTypes;

    mapping(address => uint256) public lastChosenWeek;
    uint256 public defaultPreparationWeeks;

    event RaceSessionCreated(
        uint256 indexed sessionId,
        uint256 targetWeekStart,
        uint256 prepWeeks
    );
    event SessionPaused(uint256 indexed sessionId);
    event SessionResumed(uint256 indexed sessionId);
    event SessionCancelled(uint256 indexed sessionId);
    event RaceResult(
        uint256 indexed sessionId,
        uint256 round,
        address indexed winner,
        ParticipantType pType
    );
    event SessionCompleted(
        uint256 indexed sessionId,
        address mentor,
        address[] interns
    );
    event SeminarInfoUpdated(
        uint256 indexed sessionId,
        string title,
        string description
    );
    event SeminarDateUpdated(uint256 indexed sessionId, uint256 date);
    event PreparationWeeksUpdated(uint256 indexed sessionId, uint256 newWeeks);
    event ParticipantAdded(
        address indexed participant,
        string name,
        ParticipantType pType
    );
    event ParticipantRemoved(address indexed participant);
    event InternPoolUpdated(uint256 count);
    event FulltimePoolUpdated(uint256 count);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address defaultAdmin) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(ADMIN_ROLE, defaultAdmin);
        nextSessionId = 1;
        defaultPreparationWeeks = 4;
    }

    modifier onlyAdmin() {
        require(
            hasRole(ADMIN_ROLE, msg.sender),
            "SeminarRandomizer: only admin"
        );
        _;
    }

    // ── Admin Functions — Pool Management ──

    function addParticipant(
        address _participant,
        string memory _name,
        ParticipantType _pType
    ) external onlyAdmin {
        require(
            bytes(participantNames[_participant]).length == 0,
            "Participant already exists"
        );
        participantNames[_participant] = _name;
        participantTypes[_participant] = _pType;

        if (_pType == ParticipantType.INTERN) {
            globalInternPool.push(_participant);
            emit InternPoolUpdated(globalInternPool.length);
        } else {
            globalFulltimePool.push(_participant);
            emit FulltimePoolUpdated(globalFulltimePool.length);
        }

        emit ParticipantAdded(_participant, _name, _pType);
    }

    function removeParticipant(address _participant) external onlyAdmin {
        require(
            bytes(participantNames[_participant]).length > 0,
            "Participant does not exist"
        );

        ParticipantType pType = participantTypes[_participant];
        delete participantNames[_participant];

        if (pType == ParticipantType.INTERN) {
            _removeFromPool(globalInternPool, _participant);
            emit InternPoolUpdated(globalInternPool.length);
        } else {
            _removeFromPool(globalFulltimePool, _participant);
            emit FulltimePoolUpdated(globalFulltimePool.length);
        }

        emit ParticipantRemoved(_participant);
    }

    function updateInternPool(address[] memory _newPool) external onlyAdmin {
        globalInternPool = _newPool;
        emit InternPoolUpdated(_newPool.length);
    }

    function updateFulltimePool(address[] memory _newPool) external onlyAdmin {
        globalFulltimePool = _newPool;
        emit FulltimePoolUpdated(_newPool.length);
    }

    function getParticipants(
        ParticipantType _pType
    ) external view returns (address[] memory) {
        if (_pType == ParticipantType.INTERN) return globalInternPool;
        return globalFulltimePool;
    }

    // ── Admin Functions — Session Management ──

    function createRaceSession(
        uint256 targetWeekStart
    ) external onlyAdmin returns (uint256 sessionId) {
        sessionId = nextSessionId++;

        RaceSession storage session = sessions[sessionId];
        session.sessionId = sessionId;
        session.status = SessionStatus.PENDING;
        session.createdAt = block.timestamp;
        session.targetWeekStart = targetWeekStart;
        session.preparationWeeks = defaultPreparationWeeks;

        session.internPool = _filterCooldownParticipants(
            globalInternPool,
            targetWeekStart
        );
        session.fulltimePool = _filterCooldownParticipants(
            globalFulltimePool,
            targetWeekStart
        );

        require(
            session.fulltimePool.length >= 1,
            "Not enough full-time members"
        );

        require(session.internPool.length >= 3, "Not enough intern members");

        sessionList.push(sessionId);

        emit RaceSessionCreated(
            sessionId,
            targetWeekStart,
            session.preparationWeeks
        );
    }

    function updatePreparationWeeks(
        uint256 sessionId,
        uint256 _weeks
    ) external onlyAdmin {
        require(sessions[sessionId].sessionId != 0, "Session does not exist");
        sessions[sessionId].preparationWeeks = _weeks;
        emit PreparationWeeksUpdated(sessionId, _weeks);
    }

    function setDefaultPreparationWeeks(uint256 _weeks) external onlyAdmin {
        defaultPreparationWeeks = _weeks;
    }

    function pauseSession(uint256 sessionId) external onlyAdmin {
        RaceSession storage session = sessions[sessionId];
        require(
            session.status == SessionStatus.RACING ||
                session.status == SessionStatus.COMPLETED,
            "Cannot pause in this status"
        );

        session.status = SessionStatus.PAUSED;
        emit SessionPaused(sessionId);
    }

    function resumeSession(uint256 sessionId) external onlyAdmin {
        RaceSession storage session = sessions[sessionId];
        require(session.status == SessionStatus.PAUSED, "Not paused");

        if (session.currentRound == 4) {
            session.status = SessionStatus.COMPLETED;
        } else if (session.currentRound > 0) {
            session.status = SessionStatus.RACING;
        } else {
            session.status = SessionStatus.PENDING;
        }

        emit SessionResumed(sessionId);
    }

    function cancelSession(uint256 sessionId) external onlyAdmin {
        RaceSession storage session = sessions[sessionId];
        require(session.status != SessionStatus.CANCELLED, "Already cancelled");

        // Reset cooldowns
        if (session.selectedMentor != address(0)) {
            if (
                lastChosenWeek[session.selectedMentor] ==
                session.targetWeekStart
            ) {
                lastChosenWeek[session.selectedMentor] = 0;
            }
        }
        for (uint256 i = 0; i < session.selectedInterns.length; i++) {
            if (
                lastChosenWeek[session.selectedInterns[i]] ==
                session.targetWeekStart
            ) {
                lastChosenWeek[session.selectedInterns[i]] = 0;
            }
        }

        session.status = SessionStatus.CANCELLED;
        emit SessionCancelled(sessionId);
    }

    // ── Race Functions — Randomization ──

    function startNextRace(uint256 sessionId) external onlyAdmin {
        RaceSession storage session = sessions[sessionId];
        require(
            session.status == SessionStatus.PENDING ||
                session.status == SessionStatus.RACING,
            "Invalid status"
        );
        require(session.currentRound < 4, "Race already finished");

        if (session.status == SessionStatus.PENDING) {
            session.status = SessionStatus.RACING;
        }

        session.currentRound++;

        address winner;
        ParticipantType pType;

        if (session.currentRound == 1) {
            require(session.fulltimePool.length > 0, "Empty fulltime pool");
            uint256 randomIndex = _getRandomIndex(
                sessionId,
                session.currentRound,
                session.fulltimePool.length
            );
            winner = session.fulltimePool[randomIndex];
            session.selectedMentor = winner;
            pType = ParticipantType.FULLTIME;
        } else {
            require(session.internPool.length > 0, "Empty intern pool");
            uint256 randomIndex = _getRandomIndex(
                sessionId,
                session.currentRound,
                session.internPool.length
            );
            winner = session.internPool[randomIndex];
            session.selectedInterns.push(winner);
            pType = ParticipantType.INTERN;

            // Swap and pop
            session.internPool[randomIndex] = session.internPool[
                session.internPool.length - 1
            ];
            session.internPool.pop();
        }

        emit RaceResult(sessionId, session.currentRound, winner, pType);

        if (session.currentRound == 4) {
            session.status = SessionStatus.COMPLETED;

            // Set cooldown
            lastChosenWeek[session.selectedMentor] = session.targetWeekStart;
            for (uint256 i = 0; i < session.selectedInterns.length; i++) {
                lastChosenWeek[session.selectedInterns[i]] = session
                    .targetWeekStart;
            }

            emit SessionCompleted(
                sessionId,
                session.selectedMentor,
                session.selectedInterns
            );
        }
    }

    function _getRandomIndex(
        uint256 sessionId,
        uint256 round,
        uint256 poolLength
    ) internal view returns (uint256) {
        return
            uint256(
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

    function _filterCooldownParticipants(
        address[] memory pool,
        uint256 targetWeekStart
    ) internal view returns (address[] memory) {
        // Count valid
        uint256 validCount = 0;
        uint256 weekDiff = 7 days; // 1 week in seconds
        uint256 previousWeekStart = targetWeekStart > weekDiff
            ? targetWeekStart - weekDiff
            : 0;

        for (uint256 i = 0; i < pool.length; i++) {
            if (lastChosenWeek[pool[i]] != previousWeekStart) {
                validCount++;
            }
        }

        address[] memory filtered = new address[](validCount);
        uint256 index = 0;
        for (uint256 i = 0; i < pool.length; i++) {
            if (lastChosenWeek[pool[i]] != previousWeekStart) {
                filtered[index] = pool[i];
                index++;
            }
        }

        return filtered;
    }

    function _removeFromPool(
        address[] storage pool,
        address participant
    ) internal {
        for (uint256 i = 0; i < pool.length; i++) {
            if (pool[i] == participant) {
                pool[i] = pool[pool.length - 1];
                pool.pop();
                break;
            }
        }
    }

    // ── Seminar Info Functions ──

    function updateSeminarInfo(
        uint256 sessionId,
        string memory _title,
        string memory _description
    ) external {
        RaceSession storage session = sessions[sessionId];
        require(_isTeamMemberOrAdmin(sessionId, msg.sender), "Not authorized");
        session.seminarTitle = _title;
        session.seminarDescription = _description;

        emit SeminarInfoUpdated(sessionId, _title, _description);
    }

    function updateSeminarDate(uint256 sessionId, uint256 _date) external {
        RaceSession storage session = sessions[sessionId];
        require(_isTeamMemberOrAdmin(sessionId, msg.sender), "Not authorized");

        session.seminarDate = _date;
        emit SeminarDateUpdated(sessionId, _date);
    }

    function _isTeamMemberOrAdmin(
        uint256 sessionId,
        address user
    ) internal view returns (bool) {
        if (hasRole(ADMIN_ROLE, user)) return true;

        RaceSession storage session = sessions[sessionId];
        if (session.selectedMentor == user) return true;
        for (uint256 i = 0; i < session.selectedInterns.length; i++) {
            if (session.selectedInterns[i] == user) return true;
        }

        return false;
    }

    // ── View Functions ──

    function getSession(
        uint256 sessionId
    ) external view returns (RaceSession memory) {
        return sessions[sessionId];
    }

    function getSelectedTeam(
        uint256 sessionId
    ) external view returns (address mentor, address[] memory interns) {
        RaceSession storage session = sessions[sessionId];
        return (session.selectedMentor, session.selectedInterns);
    }

    function getUpcomingSessions() external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < sessionList.length; i++) {
            SessionStatus s = sessions[sessionList[i]].status;
            if (
                s == SessionStatus.RACING ||
                s == SessionStatus.PENDING ||
                (s == SessionStatus.COMPLETED &&
                    sessions[sessionList[i]].seminarDate >= block.timestamp)
            ) {
                count++;
            }
        }

        uint256[] memory upcoming = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < sessionList.length; i++) {
            SessionStatus s = sessions[sessionList[i]].status;
            if (
                s == SessionStatus.RACING ||
                s == SessionStatus.PENDING ||
                (s == SessionStatus.COMPLETED &&
                    sessions[sessionList[i]].seminarDate >= block.timestamp)
            ) {
                upcoming[index] = sessionList[i];
                index++;
            }
        }
        return upcoming;
    }

    function getPastSessions() external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < sessionList.length; i++) {
            SessionStatus s = sessions[sessionList[i]].status;
            if (
                s == SessionStatus.COMPLETED &&
                sessions[sessionList[i]].seminarDate < block.timestamp
            ) {
                count++;
            }
        }

        uint256[] memory past = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < sessionList.length; i++) {
            SessionStatus s = sessions[sessionList[i]].status;
            if (
                s == SessionStatus.COMPLETED &&
                sessions[sessionList[i]].seminarDate < block.timestamp
            ) {
                past[index] = sessionList[i];
                index++;
            }
        }
        return past;
    }

    function getRemainingInternPool(
        uint256 sessionId
    ) external view returns (address[] memory) {
        return sessions[sessionId].internPool;
    }

    function getFulltimePool(
        uint256 sessionId
    ) external view returns (address[] memory) {
        return sessions[sessionId].fulltimePool;
    }

    function isOnCooldown(
        address participant,
        uint256 targetWeekStart
    ) external view returns (bool) {
        uint256 weekDiff = 7 days;
        uint256 previousWeekStart = targetWeekStart > weekDiff
            ? targetWeekStart - weekDiff
            : 0;
        return
            lastChosenWeek[participant] == previousWeekStart &&
            previousWeekStart != 0;
    }

    function getAllSessions() external view returns (uint256[] memory) {
        return sessionList;
    }
}
