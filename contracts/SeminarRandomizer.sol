// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface ISpeakerManager {
    function speakerExists(address _speaker) external view returns (bool);
}

interface ISeminarManager {
    function seminarExists(uint256 _seminarId) external view returns (bool);
}

/// @title Seminar Randomizer Contract
/// @notice Manages participant pools, randomized pick logic, and week-based seminar sessions
contract SeminarRandomizer is Initializable, AccessControlUpgradeable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

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
        uint256 requiredFulltimes;
        uint256 requiredInterns;
        bytes32 sessionSeed;
        address[] internPool;
        address[] fulltimePool;
        address[] selectedFulltimes;
        address[] selectedInterns;
        uint256 currentRound;
        string seminarTitle;
        string seminarDescription;
        uint256 seminarDate;
        uint256 seminarId;
        bool usedCooldownFallback;
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

    address public speakerManager;
    address public seminarManager;

    event RaceSessionCreated(
        uint256 indexed sessionId,
        uint256 targetWeekStart,
        uint256 prepWeeks,
        uint256 requiredFulltimes,
        uint256 requiredInterns
    );
    event SessionPaused(uint256 indexed sessionId);
    event SessionResumed(uint256 indexed sessionId);
    event SessionCancelled(uint256 indexed sessionId);
    event SessionWeekUpdated(uint256 indexed sessionId, uint256 previousWeekStart, uint256 newWeekStart);
    event RaceResult(
        uint256 indexed sessionId,
        uint256 round,
        address indexed winner,
        ParticipantType pType
    );
    event SessionCompleted(
        uint256 indexed sessionId,
        address[] fulltimes,
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
    event SourceContractsUpdated(address indexed speakerManager, address indexed seminarManager);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract and sets the default admin
    /// @param defaultAdmin Address to be granted the DEFAULT_ADMIN_ROLE and ADMIN_ROLE
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

    // ── Admin Functions — Cross-Contract Sources ──

    /// @notice Sets source contracts used for cross-reference checks
    /// @dev Set address(0) to disable a source check temporarily
    function setSourceContracts(address _speakerManager, address _seminarManager) external onlyAdmin {
        speakerManager = _speakerManager;
        seminarManager = _seminarManager;
        emit SourceContractsUpdated(_speakerManager, _seminarManager);
    }

    // ── Admin Functions — Pool Management ──

    /// @notice Adds a new participant to the respective pool
    /// @dev Reverts if the participant already exists
    /// @param _participant The address of the participant
    /// @param _name The name of the participant
    /// @param _pType The type of the participant (INTERN or FULLTIME)
    function addParticipant(
        address _participant,
        string memory _name,
        ParticipantType _pType
    ) external onlyAdmin {
        _addParticipant(_participant, _name, _pType);
    }

    /// @notice Adds multiple participants in one transaction
    function batchAddParticipants(
        address[] memory _participants,
        string[] memory _names,
        ParticipantType[] memory _types
    ) external onlyAdmin {
        require(_participants.length == _names.length, "Length mismatch");
        require(_participants.length == _types.length, "Length mismatch");

        for (uint256 i = 0; i < _participants.length; i++) {
            _addParticipant(_participants[i], _names[i], _types[i]);
        }
    }

    /// @notice Removes an existing participant from the system
    /// @dev Reverts if the participant does not exist
    /// @param _participant The address of the participant to remove
    function removeParticipant(address _participant) external onlyAdmin {
        _removeParticipant(_participant);
    }

    /// @notice Removes multiple participants in one transaction
    function batchRemoveParticipants(address[] memory _participants) external onlyAdmin {
        for (uint256 i = 0; i < _participants.length; i++) {
            _removeParticipant(_participants[i]);
        }
    }

    /// @notice Sets a completely new list for the global intern pool
    /// @param _newPool The new array of intern addresses
    function updateInternPool(address[] memory _newPool) external onlyAdmin {
        globalInternPool = _newPool;
        emit InternPoolUpdated(_newPool.length);
    }

    /// @notice Sets a completely new list for the global full-time pool
    /// @param _newPool The new array of full-time participant addresses
    function updateFulltimePool(address[] memory _newPool) external onlyAdmin {
        globalFulltimePool = _newPool;
        emit FulltimePoolUpdated(_newPool.length);
    }

    /// @notice Retrieves all participant addresses of a specific type
    /// @param _pType The participant type (INTERN or FULLTIME)
    /// @return An array of participant addresses
    function getParticipants(
        ParticipantType _pType
    ) external view returns (address[] memory) {
        if (_pType == ParticipantType.INTERN) return globalInternPool;
        return globalFulltimePool;
    }

    // ── Admin Functions — Session Management ──

    /// @notice Creates a new race session with default scheduling
    function createRaceSession(
        uint256 _reqFulltimes,
        uint256 _reqInterns
    ) external onlyAdmin returns (uint256 sessionId) {
        uint256 targetTimestamp = block.timestamp + (defaultPreparationWeeks * 1 weeks);
        uint256 targetWeekStart = _getMonday(targetTimestamp);

        return _createRaceSession(0, targetWeekStart, _reqFulltimes, _reqInterns, false, defaultPreparationWeeks);
    }

    /// @notice Creates a race session for an explicit week and seminar
    function createRaceSessionForWeek(
        uint256 _seminarId,
        uint256 _targetWeekStart,
        uint256 _reqFulltimes,
        uint256 _reqInterns,
        bool _allowCooldownFallback
    ) external onlyAdmin returns (uint256 sessionId) {
        require(_isMondayStart(_targetWeekStart), "Week must be Monday 00:00 UTC");
        return _createRaceSession(
            _seminarId,
            _targetWeekStart,
            _reqFulltimes,
            _reqInterns,
            _allowCooldownFallback,
            defaultPreparationWeeks
        );
    }

    /// @notice Updates a pending session target week and refreshes candidate pools
    function updateSessionWeek(
        uint256 sessionId,
        uint256 _newWeekStart,
        bool _allowCooldownFallback
    ) external onlyAdmin {
        require(_isMondayStart(_newWeekStart), "Week must be Monday 00:00 UTC");

        RaceSession storage session = sessions[sessionId];
        require(session.sessionId != 0, "Session does not exist");
        require(session.status == SessionStatus.PENDING, "Only pending session");

        uint256 previousWeekStart = session.targetWeekStart;
        session.targetWeekStart = _newWeekStart;
        session.internPool = _filterCooldownParticipants(globalInternPool, _newWeekStart);
        session.fulltimePool = _filterCooldownParticipants(globalFulltimePool, _newWeekStart);
        session.usedCooldownFallback = false;

        if (_allowCooldownFallback) {
            if (session.fulltimePool.length < session.requiredFulltimes) {
                session.fulltimePool = globalFulltimePool;
                session.usedCooldownFallback = true;
            }
            if (session.internPool.length < session.requiredInterns) {
                session.internPool = globalInternPool;
                session.usedCooldownFallback = true;
            }
        }

        require(
            session.fulltimePool.length >= session.requiredFulltimes,
            "Not enough full-time members"
        );
        require(
            session.internPool.length >= session.requiredInterns,
            "Not enough intern members"
        );

        emit SessionWeekUpdated(sessionId, previousWeekStart, _newWeekStart);
    }

    /// @notice Updates the allotted preparation weeks for an existing session
    /// @param sessionId The ID of the targeted session
    /// @param _weeks The new amount of preparation weeks
    function updatePreparationWeeks(
        uint256 sessionId,
        uint256 _weeks
    ) external onlyAdmin {
        require(sessions[sessionId].sessionId != 0, "Session does not exist");
        sessions[sessionId].preparationWeeks = _weeks;
        emit PreparationWeeksUpdated(sessionId, _weeks);
    }

    /// @notice Updates the default duration of preparation weeks for new sessions
    /// @param _weeks The new default preparation duration
    function setDefaultPreparationWeeks(uint256 _weeks) external onlyAdmin {
        defaultPreparationWeeks = _weeks;
    }

    /// @notice Manually sets/overwrites a selected team for a session
    /// @dev Useful for UI-driven edits when availability changes
    function setSelectedTeam(
        uint256 sessionId,
        address[] memory _fulltimes,
        address[] memory _interns,
        bool _ignoreCooldownCheck
    ) external onlyAdmin {
        RaceSession storage session = sessions[sessionId];
        require(session.sessionId != 0, "Session does not exist");
        require(session.status != SessionStatus.CANCELLED, "Session cancelled");
        require(_fulltimes.length == session.requiredFulltimes, "Invalid fulltime count");
        require(_interns.length == session.requiredInterns, "Invalid intern count");

        _validateTeam(_fulltimes, _interns, session.targetWeekStart, _ignoreCooldownCheck);

        _clearSessionCooldown(session);

        session.selectedFulltimes = _fulltimes;
        session.selectedInterns = _interns;
        session.currentRound = session.requiredFulltimes + session.requiredInterns;
        session.status = SessionStatus.COMPLETED;

        _applySessionCooldown(session);

        emit SessionCompleted(sessionId, session.selectedFulltimes, session.selectedInterns);
    }

    /// @notice Pauses an ongoing or completed session
    /// @dev Can only be paused if RACING or COMPLETED
    /// @param sessionId The ID of the session to pause
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

    /// @notice Resumes a previously paused session, returning it to its former state
    /// @dev Reverts if the session is not paused
    /// @param sessionId The ID of the session to resume
    function resumeSession(uint256 sessionId) external onlyAdmin {
        RaceSession storage session = sessions[sessionId];
        require(session.status == SessionStatus.PAUSED, "Not paused");

        if (session.selectedFulltimes.length == session.requiredFulltimes && session.selectedInterns.length == session.requiredInterns) {
            session.status = SessionStatus.COMPLETED;
        } else if (session.currentRound > 0) {
            session.status = SessionStatus.RACING;
        } else {
            session.status = SessionStatus.PENDING;
        }

        emit SessionResumed(sessionId);
    }

    /// @notice Cancels an active session and removes cooldowns applied to selected candidates
    /// @dev Reverts if the session is already cancelled
    /// @param sessionId The ID of the session to cancel
    function cancelSession(uint256 sessionId) external onlyAdmin {
        RaceSession storage session = sessions[sessionId];
        require(session.status != SessionStatus.CANCELLED, "Already cancelled");

        _clearSessionCooldown(session);

        session.status = SessionStatus.CANCELLED;
        emit SessionCancelled(sessionId);
    }

    // ── Race Functions — Randomization ──

    /// @notice Start the next round of a seminar race
    /// @param sessionId The ID of the session to run the race for
    function startNextRace(uint256 sessionId) external onlyAdmin {
        RaceSession storage session = sessions[sessionId];
        require(
            session.status == SessionStatus.PENDING ||
                session.status == SessionStatus.RACING,
            "Invalid status"
        );
        require(
            session.currentRound < (session.requiredFulltimes + session.requiredInterns),
            "Race already finished"
        );

        if (session.status == SessionStatus.PENDING) {
            session.status = SessionStatus.RACING;
        }

        session.currentRound++;

        // Update seed every round
        session.sessionSeed = keccak256(abi.encodePacked(session.sessionSeed, session.currentRound));

        address winner;
        ParticipantType pType;

        if (session.selectedFulltimes.length < session.requiredFulltimes) {
            require(session.fulltimePool.length > 0, "Empty fulltime pool");
            uint256 randomIndex = uint256(session.sessionSeed) % session.fulltimePool.length;
            winner = session.fulltimePool[randomIndex];
            session.selectedFulltimes.push(winner);
            pType = ParticipantType.FULLTIME;

            // Swap and pop
            session.fulltimePool[randomIndex] = session.fulltimePool[
                session.fulltimePool.length - 1
            ];
            session.fulltimePool.pop();
        } else {
            require(session.internPool.length > 0, "Empty intern pool");
            uint256 randomIndex = uint256(session.sessionSeed) % session.internPool.length;
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

        if (session.selectedFulltimes.length == session.requiredFulltimes && session.selectedInterns.length == session.requiredInterns) {
            session.status = SessionStatus.COMPLETED;
            _applySessionCooldown(session);

            emit SessionCompleted(
                sessionId,
                session.selectedFulltimes,
                session.selectedInterns
            );
        }
    }

    function _createRaceSession(
        uint256 _seminarId,
        uint256 _targetWeekStart,
        uint256 _reqFulltimes,
        uint256 _reqInterns,
        bool _allowCooldownFallback,
        uint256 _preparationWeeks
    ) internal returns (uint256 sessionId) {
        require(_reqFulltimes > 0 || _reqInterns > 0, "Invalid requirements");
        if (seminarManager != address(0) && _seminarId != 0) {
            require(ISeminarManager(seminarManager).seminarExists(_seminarId), "Unknown seminar");
        }

        sessionId = nextSessionId++;

        RaceSession storage session = sessions[sessionId];
        session.sessionId = sessionId;
        session.status = SessionStatus.PENDING;
        session.createdAt = block.timestamp;
        session.targetWeekStart = _targetWeekStart;
        session.preparationWeeks = _preparationWeeks;
        session.requiredFulltimes = _reqFulltimes;
        session.requiredInterns = _reqInterns;
        session.sessionSeed = keccak256(abi.encodePacked(block.prevrandao, sessionId));
        session.seminarId = _seminarId;
        session.usedCooldownFallback = false;

        session.internPool = _filterCooldownParticipants(
            globalInternPool,
            _targetWeekStart
        );
        session.fulltimePool = _filterCooldownParticipants(
            globalFulltimePool,
            _targetWeekStart
        );

        if (_allowCooldownFallback) {
            if (session.fulltimePool.length < _reqFulltimes) {
                session.fulltimePool = globalFulltimePool;
                session.usedCooldownFallback = true;
            }
            if (session.internPool.length < _reqInterns) {
                session.internPool = globalInternPool;
                session.usedCooldownFallback = true;
            }
        }

        require(
            session.fulltimePool.length >= _reqFulltimes,
            "Not enough full-time members"
        );

        require(
            session.internPool.length >= _reqInterns,
            "Not enough intern members"
        );

        sessionList.push(sessionId);

        emit RaceSessionCreated(
            sessionId,
            _targetWeekStart,
            session.preparationWeeks,
            _reqFulltimes,
            _reqInterns
        );
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

    function _contains(address[] storage pool, address participant) internal view returns (bool) {
        for (uint256 i = 0; i < pool.length; i++) {
            if (pool[i] == participant) {
                return true;
            }
        }
        return false;
    }

    function _addParticipant(
        address _participant,
        string memory _name,
        ParticipantType _pType
    ) internal {
        require(_participant != address(0), "Invalid participant");
        require(bytes(_name).length > 0, "Empty name");
        require(
            bytes(participantNames[_participant]).length == 0,
            "Participant already exists"
        );
        if (speakerManager != address(0)) {
            require(ISpeakerManager(speakerManager).speakerExists(_participant), "Unknown speaker");
        }

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

    function _removeParticipant(address _participant) internal {
        require(
            bytes(participantNames[_participant]).length > 0,
            "Participant does not exist"
        );

        ParticipantType pType = participantTypes[_participant];
        delete participantNames[_participant];
        delete participantTypes[_participant];

        if (pType == ParticipantType.INTERN) {
            _removeFromPool(globalInternPool, _participant);
            emit InternPoolUpdated(globalInternPool.length);
        } else {
            _removeFromPool(globalFulltimePool, _participant);
            emit FulltimePoolUpdated(globalFulltimePool.length);
        }

        emit ParticipantRemoved(_participant);
    }

    function _validateTeam(
        address[] memory _fulltimes,
        address[] memory _interns,
        uint256 _targetWeekStart,
        bool _ignoreCooldownCheck
    ) internal view {
        for (uint256 i = 0; i < _fulltimes.length; i++) {
            _validateParticipantForTeam(
                _fulltimes[i],
                ParticipantType.FULLTIME,
                _targetWeekStart,
                _ignoreCooldownCheck
            );
            require(!_hasDuplicateInTail(_fulltimes, i), "Duplicate fulltime");
            require(!_existsInArray(_interns, _fulltimes[i]), "Duplicate participant");
        }

        for (uint256 i = 0; i < _interns.length; i++) {
            _validateParticipantForTeam(
                _interns[i],
                ParticipantType.INTERN,
                _targetWeekStart,
                _ignoreCooldownCheck
            );
            require(!_hasDuplicateInTail(_interns, i), "Duplicate intern");
        }
    }

    function _validateParticipantForTeam(
        address member,
        ParticipantType expectedType,
        uint256 targetWeekStart,
        bool ignoreCooldownCheck
    ) internal view {
        require(bytes(participantNames[member]).length > 0, "Unknown participant");
        require(participantTypes[member] == expectedType, "Type mismatch");
        if (expectedType == ParticipantType.FULLTIME) {
            require(_contains(globalFulltimePool, member), "Not in fulltime pool");
        } else {
            require(_contains(globalInternPool, member), "Not in intern pool");
        }
        if (!ignoreCooldownCheck) {
            require(!_isOnCooldownForWeek(member, targetWeekStart), "Participant on cooldown");
        }
    }

    function _hasDuplicateInTail(
        address[] memory values,
        uint256 index
    ) internal pure returns (bool) {
        for (uint256 j = index + 1; j < values.length; j++) {
            if (values[j] == values[index]) {
                return true;
            }
        }
        return false;
    }

    function _existsInArray(
        address[] memory values,
        address value
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < values.length; i++) {
            if (values[i] == value) {
                return true;
            }
        }
        return false;
    }

    function _clearSessionCooldown(RaceSession storage session) internal {
        for (uint256 i = 0; i < session.selectedFulltimes.length; i++) {
            if (
                lastChosenWeek[session.selectedFulltimes[i]] ==
                session.targetWeekStart
            ) {
                lastChosenWeek[session.selectedFulltimes[i]] = 0;
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
    }

    function _applySessionCooldown(RaceSession storage session) internal {
        for (uint256 i = 0; i < session.selectedFulltimes.length; i++) {
            lastChosenWeek[session.selectedFulltimes[i]] = session.targetWeekStart;
        }
        for (uint256 i = 0; i < session.selectedInterns.length; i++) {
            lastChosenWeek[session.selectedInterns[i]] = session.targetWeekStart;
        }
    }

    // ── Seminar Info Functions ──

    /// @notice Update seminar title and description manually
    /// @dev Can only be called by an admin or a member of the selected team for this session
    /// @param sessionId The target session ID
    /// @param _title The proposed newly drafted title
    /// @param _description The proposed description
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

    /// @notice Update the official seminar date
    /// @dev Can only be called by an admin or a member of the selected team for this session
    /// @param sessionId The target session ID
    /// @param _date The Unix timestamp of the final seminar date
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
        for (uint256 i = 0; i < session.selectedFulltimes.length; i++) {
            if (session.selectedFulltimes[i] == user) return true;
        }
        for (uint256 i = 0; i < session.selectedInterns.length; i++) {
            if (session.selectedInterns[i] == user) return true;
        }

        return false;
    }

    function _getMonday(uint256 t) internal pure returns (uint256) {
        uint256 daysSinceEpoch = t / 86400; // 0 = Thursday
        uint256 dayOfWeek = (daysSinceEpoch + 4) % 7; // 0 = Sunday, 1 = Monday
        uint256 offsetDaysFromMonday = (dayOfWeek + 6) % 7;
        uint256 startOfDay = t - (t % 86400);
        return startOfDay - (offsetDaysFromMonday * 86400);
    }

    function _isMondayStart(uint256 t) internal pure returns (bool) {
        return _getMonday(t) == t;
    }

    function _isOnCooldownForWeek(
        address participant,
        uint256 targetWeekStart
    ) internal view returns (bool) {
        uint256 weekDiff = 7 days;
        uint256 previousWeekStart = targetWeekStart > weekDiff
            ? targetWeekStart - weekDiff
            : 0;
        return
            lastChosenWeek[participant] == previousWeekStart &&
            previousWeekStart != 0;
    }

    // ── View Functions ──

    /// @notice Gets the core session struct holding all its data
    /// @param sessionId The targeted session ID
    /// @return The complete RaceSession struct
    function getSession(
        uint256 sessionId
    ) external view returns (RaceSession memory) {
        return sessions[sessionId];
    }

    /// @notice Returns the selected mentors and interns for a session
    /// @param sessionId The targeted session ID
    /// @return fulltimes The selected mentor addresses
    /// @return interns Array of selected intern addresses
    function getSelectedTeam(
        uint256 sessionId
    ) external view returns (address[] memory fulltimes, address[] memory interns) {
        RaceSession storage session = sessions[sessionId];
        return (session.selectedFulltimes, session.selectedInterns);
    }

    /// @notice Retrieves a list of upcoming or concurrently active/pending session IDs
    /// @return An array of active or upcoming session IDs
    function getUpcomingSessions() external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < sessionList.length; i++) {
            SessionStatus s = sessions[sessionList[i]].status;
            if (
                s == SessionStatus.RACING ||
                s == SessionStatus.PENDING ||
                s == SessionStatus.PAUSED ||
                (s == SessionStatus.COMPLETED &&
                    sessions[sessionList[i]].targetWeekStart >= block.timestamp)
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
                s == SessionStatus.PAUSED ||
                (s == SessionStatus.COMPLETED &&
                    sessions[sessionList[i]].targetWeekStart >= block.timestamp)
            ) {
                upcoming[index] = sessionList[i];
                index++;
            }
        }
        return upcoming;
    }

    /// @notice Retrieves a list of completed past session IDs where targetWeekStart is already passed
    /// @return An array of past session IDs
    function getPastSessions() external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < sessionList.length; i++) {
            SessionStatus s = sessions[sessionList[i]].status;
            if (
                s == SessionStatus.COMPLETED &&
                sessions[sessionList[i]].targetWeekStart < block.timestamp
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
                sessions[sessionList[i]].targetWeekStart < block.timestamp
            ) {
                past[index] = sessionList[i];
                index++;
            }
        }
        return past;
    }

    /// @notice Reads the current unselected intern pool dynamically bound to a specific session
    /// @param sessionId The target session ID
    /// @return The unselected intern pool as an array of addresses
    function getRemainingInternPool(
        uint256 sessionId
    ) external view returns (address[] memory) {
        return sessions[sessionId].internPool;
    }

    /// @notice Reads the pool of full-time mentors bound to a specific session before mentor selection
    /// @param sessionId The targeted session ID
    /// @return The full-time mentor pool array
    function getFulltimePool(
        uint256 sessionId
    ) external view returns (address[] memory) {
        return sessions[sessionId].fulltimePool;
    }

    /// @notice Returns whether a participant is on cooldown and cannot be chosen for a targeted week
    /// @param participant The participant's address
    /// @param targetWeekStart The Unix timestamp marking the start of the week for the intended session
    /// @return True if participant is currently on cooldown; false otherwise
    function isOnCooldown(
        address participant,
        uint256 targetWeekStart
    ) external view returns (bool) {
        return _isOnCooldownForWeek(participant, targetWeekStart);
    }

    /// @notice Gets all ever-created or registered session IDs globally
    /// @return An array of all tracked session IDs
    function getAllSessions() external view returns (uint256[] memory) {
        return sessionList;
    }
}
