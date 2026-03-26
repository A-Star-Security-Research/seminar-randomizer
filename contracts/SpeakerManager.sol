// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title Speaker Manager Contract
/// @notice Manages speakers and their assigned seminars
contract SpeakerManager is Initializable, AccessControlUpgradeable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    struct Speaker {
        string name;
        address speakerAddress;
        uint256[] seminarIds;
    }

    mapping(address => Speaker) public speakers;
    address[] public speakerList;

    event SpeakerAdded(address indexed speaker, string name);
    event SpeakerUpdated(address indexed speaker, string name);
    event SpeakerRemoved(address indexed speaker);
    event SeminarAddedToSpeaker(address indexed speaker, uint256 seminarId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract and sets the default admin
    /// @param defaultAdmin The address to be granted the DEFAULT_ADMIN_ROLE and ADMIN_ROLE
    function initialize(address defaultAdmin) initializer public {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(ADMIN_ROLE, defaultAdmin);
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "SpeakerManager: only admin");
        _;
    }

    /// @notice Adds a new speaker to the manager
    /// @dev Reverts if the speaker already exists
    /// @param _speaker The address of the speaker
    /// @param _name The name of the speaker
    function addSpeaker(address _speaker, string memory _name) external onlyAdmin {
        _addSpeaker(_speaker, _name);
    }

    /// @notice Adds multiple speakers in one transaction
    /// @param _speakers The addresses of speakers
    /// @param _names The corresponding speaker names
    function batchAddSpeakers(address[] memory _speakers, string[] memory _names) external onlyAdmin {
        require(_speakers.length == _names.length, "SpeakerManager: length mismatch");
        for (uint256 i = 0; i < _speakers.length; i++) {
            _addSpeaker(_speakers[i], _names[i]);
        }
    }

    /// @notice Updates the name of an existing speaker
    /// @dev Reverts if the speaker does not exist
    /// @param _speaker The address of the expected speaker
    /// @param _name The new name for the speaker
    function updateSpeaker(address _speaker, string memory _name) external onlyAdmin {
        require(bytes(speakers[_speaker].name).length > 0, "SpeakerManager: speaker does not exist");

        speakers[_speaker].name = _name;

        emit SpeakerUpdated(_speaker, _name);
    }

    /// @notice Removes a speaker from the manager
    /// @dev Reverts if the speaker does not exist
    /// @param _speaker The address of the speaker to remove
    function removeSpeaker(address _speaker) external onlyAdmin {
        _removeSpeaker(_speaker);
    }

    /// @notice Removes multiple speakers in one transaction
    /// @param _speakers The speaker addresses to remove
    function batchRemoveSpeakers(address[] memory _speakers) external onlyAdmin {
        for (uint256 i = 0; i < _speakers.length; i++) {
            _removeSpeaker(_speakers[i]);
        }
    }

    /// @notice Links a seminar ID to a specific speaker
    /// @dev Reverts if the speaker does not exist
    /// @param _speaker The address of the speaker
    /// @param _seminarId The ID of the seminar to add
    function addSeminarToSpeaker(address _speaker, uint256 _seminarId) external onlyAdmin {
        require(bytes(speakers[_speaker].name).length > 0, "SpeakerManager: speaker does not exist");
        speakers[_speaker].seminarIds.push(_seminarId);
        emit SeminarAddedToSpeaker(_speaker, _seminarId);
    }

    /// @notice Retrieves the details of a specific speaker
    /// @param _speaker The address of the speaker
    /// @return The Speaker struct containing their details
    function getSpeaker(address _speaker) external view returns (Speaker memory) {
        return speakers[_speaker];
    }

    /// @notice Checks whether a speaker exists
    function speakerExists(address _speaker) external view returns (bool) {
        return bytes(speakers[_speaker].name).length > 0;
    }

    /// @notice Retrieves the list of all registered speaker addresses
    /// @return An array of speaker addresses
    function getAllSpeakers() external view returns (address[] memory) {
        return speakerList;
    }

    /// @notice Retrieves the list of seminar IDs assigned to a specific speaker
    /// @param _speaker The address of the speaker
    /// @return An array of seminar IDs
    function getSpeakerSeminars(address _speaker) external view returns (uint256[] memory) {
        return speakers[_speaker].seminarIds;
    }

    function _addSpeaker(address _speaker, string memory _name) internal {
        require(_speaker != address(0), "SpeakerManager: zero address");
        require(bytes(_name).length > 0, "SpeakerManager: empty name");
        require(bytes(speakers[_speaker].name).length == 0, "SpeakerManager: speaker already exists");

        speakers[_speaker].name = _name;
        speakers[_speaker].speakerAddress = _speaker;
        speakerList.push(_speaker);

        emit SpeakerAdded(_speaker, _name);
    }

    function _removeSpeaker(address _speaker) internal {
        require(bytes(speakers[_speaker].name).length > 0, "SpeakerManager: speaker does not exist");

        delete speakers[_speaker];

        // Remove from list
        for (uint256 i = 0; i < speakerList.length; i++) {
            if (speakerList[i] == _speaker) {
                // Swap and pop
                speakerList[i] = speakerList[speakerList.length - 1];
                speakerList.pop();
                break;
            }
        }

        emit SpeakerRemoved(_speaker);
    }
}
