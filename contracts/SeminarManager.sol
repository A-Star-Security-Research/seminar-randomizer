// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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

    function updateSeminarInfo(uint256 _seminarId, string memory _title, string memory _description) external onlyAdmin {
        require(seminars[_seminarId].id != 0, "SeminarManager: seminar does not exist");
        seminars[_seminarId].title = _title;
        seminars[_seminarId].description = _description;

        emit SeminarUpdated(_seminarId, _title);
    }

    function updateSlideLink(uint256 _seminarId, string memory _slideLink) external onlyAdmin {
        require(seminars[_seminarId].id != 0, "SeminarManager: seminar does not exist");
        seminars[_seminarId].slideLink = _slideLink;

        emit SlideLinkUpdated(_seminarId, _slideLink);
    }

    function getSeminar(uint256 _seminarId) external view returns (Seminar memory) {
        return seminars[_seminarId];
    }

    function getAllSeminars() external view returns (uint256[] memory) {
        return seminarList;
    }
}
