// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title Seminar Manager Contract
/// @notice Manages seminar sessions and their corresponding data
contract SeminarManager is Initializable, AccessControlUpgradeable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    struct Seminar {
        uint256 id;
        string title;
        string description;
        string slideLink;
        address[] speakers;
        uint256 createdAt;
    }

    mapping(uint256 => Seminar) public seminars;
    uint256 public nextSeminarId;
    uint256[] public seminarList;

    event SeminarCreated(uint256 indexed seminarId, string title, address[] speakers);
    event SeminarUpdated(uint256 indexed seminarId, string title);
    event SlideLinkUpdated(uint256 indexed seminarId, string slideLink);
    event SeminarSpeakersUpdated(uint256 indexed seminarId, address[] speakers);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract and sets the default admin
    /// @param defaultAdmin Address to be granted the DEFAULT_ADMIN_ROLE and ADMIN_ROLE
    function initialize(address defaultAdmin) initializer public {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(ADMIN_ROLE, defaultAdmin);
        nextSeminarId = 1;
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "SeminarManager: only admin");
        _;
    }

    /// @notice Creates a new seminar with title, description, slide link, and speakers
    /// @param _title The title of the seminar
    /// @param _description The description of the seminar
    /// @param _slideLink The URL link to the seminar slides
    /// @param _speakers An array of speaker addresses involved
    /// @return seminarId The ID of the newly created seminar
    function createSeminar(
        string memory _title,
        string memory _description,
        string memory _slideLink,
        address[] memory _speakers
    ) external onlyAdmin returns (uint256 seminarId) {
        seminarId = nextSeminarId++;

        Seminar storage s = seminars[seminarId];
        s.id = seminarId;
        s.title = _title;
        s.description = _description;
        s.slideLink = _slideLink;
        s.speakers = _speakers;
        s.createdAt = block.timestamp;

        seminarList.push(seminarId);

        emit SeminarCreated(seminarId, _title, _speakers);
    }

    /// @notice Updates the title and description of an existing seminar
    /// @dev Reverts if the seminar ID does not exist
    /// @param _seminarId The ID of the seminar to update
    /// @param _title The new title of the seminar
    /// @param _description The new description of the seminar
    function updateSeminarInfo(uint256 _seminarId, string memory _title, string memory _description) external onlyAdmin {
        require(seminars[_seminarId].id != 0, "SeminarManager: seminar does not exist");
        seminars[_seminarId].title = _title;
        seminars[_seminarId].description = _description;

        emit SeminarUpdated(_seminarId, _title);
    }

    /// @notice Updates the slide link for an existing seminar
    /// @dev Reverts if the seminar ID does not exist
    /// @param _seminarId The ID of the seminar to update
    /// @param _slideLink The new slide URL
    function updateSlideLink(uint256 _seminarId, string memory _slideLink) external onlyAdmin {
        require(seminars[_seminarId].id != 0, "SeminarManager: seminar does not exist");
        seminars[_seminarId].slideLink = _slideLink;

        emit SlideLinkUpdated(_seminarId, _slideLink);
    }

    /// @notice Replaces the speaker list for a seminar
    function setSeminarSpeakers(uint256 _seminarId, address[] memory _speakers) external onlyAdmin {
        require(seminars[_seminarId].id != 0, "SeminarManager: seminar does not exist");
        seminars[_seminarId].speakers = _speakers;
        emit SeminarSpeakersUpdated(_seminarId, _speakers);
    }

    /// @notice Adds multiple speakers to a seminar if they are not already present
    function addSpeakersToSeminar(uint256 _seminarId, address[] memory _speakers) external onlyAdmin {
        require(seminars[_seminarId].id != 0, "SeminarManager: seminar does not exist");

        Seminar storage s = seminars[_seminarId];
        for (uint256 i = 0; i < _speakers.length; i++) {
            if (!_containsAddress(s.speakers, _speakers[i])) {
                s.speakers.push(_speakers[i]);
            }
        }

        emit SeminarSpeakersUpdated(_seminarId, s.speakers);
    }

    /// @notice Removes multiple speakers from a seminar
    function removeSpeakersFromSeminar(uint256 _seminarId, address[] memory _speakers) external onlyAdmin {
        require(seminars[_seminarId].id != 0, "SeminarManager: seminar does not exist");

        Seminar storage s = seminars[_seminarId];
        for (uint256 i = 0; i < _speakers.length; i++) {
            _removeAddress(s.speakers, _speakers[i]);
        }

        emit SeminarSpeakersUpdated(_seminarId, s.speakers);
    }

    /// @notice Retrieves the full details of a seminar
    /// @param _seminarId The ID of the seminar
    /// @return The Seminar struct details
    function getSeminar(uint256 _seminarId) external view returns (Seminar memory) {
        return seminars[_seminarId];
    }

    /// @notice Checks if a seminar exists
    function seminarExists(uint256 _seminarId) external view returns (bool) {
        return seminars[_seminarId].id != 0;
    }

    /// @notice Retrieves the list of all created seminar IDs
    /// @return An array of seminar IDs
    function getAllSeminars() external view returns (uint256[] memory) {
        return seminarList;
    }

    function _containsAddress(address[] storage values, address value) internal view returns (bool) {
        for (uint256 i = 0; i < values.length; i++) {
            if (values[i] == value) {
                return true;
            }
        }
        return false;
    }

    function _removeAddress(address[] storage values, address value) internal {
        for (uint256 i = 0; i < values.length; i++) {
            if (values[i] == value) {
                values[i] = values[values.length - 1];
                values.pop();
                break;
            }
        }
    }
}
