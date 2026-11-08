// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title VolunteerHoursTracker
/// @notice Volunteers log hours, verifiers approve or reject them. Testing only.
contract VolunteerHoursTracker {
    enum Status { Pending, Approved, Rejected, Cancelled }

    struct Entry {
        uint256 id;
        address volunteer;
        string activity;
        uint32 minutesWorked;
        uint64 activityDate; // unix seconds, when the work happened
        uint64 submittedAt;  // unix seconds, when it was logged
        Status status;
        address reviewer;
        string note;
    }

    uint32 public constant MAX_MINUTES_PER_ENTRY = 1440; // 24 h
    uint256 public constant MAX_ACTIVITY_BYTES = 140;

    address public owner;
    mapping(address => bool) public isVerifier;

    Entry[] private entries;
    mapping(address => uint256[]) private entryIdsOf;
    mapping(address => uint256) public approvedMinutes;
    mapping(address => bool) private known;
    address[] private volunteers;
    uint256 public totalApprovedMinutes;

    event HoursLogged(uint256 indexed id, address indexed volunteer, uint32 minutesWorked, string activity);
    event HoursReviewed(uint256 indexed id, address indexed reviewer, bool approved, string note);
    event EntryCancelled(uint256 indexed id, address indexed volunteer);
    event VerifierSet(address indexed who, bool allowed);
    event OwnershipTransferred(address indexed from, address indexed to);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyVerifier() {
        require(isVerifier[msg.sender], "Only verifier");
        _;
    }

    constructor() {
        owner = msg.sender;
        isVerifier[msg.sender] = true;
        emit VerifierSet(msg.sender, true);
    }

    // ---------------------------------------------------------------- volunteers

    /// @param activityDate unix seconds of the work; pass 0 to use the current block time
    function logHours(
        string calldata activity,
        uint32 minutesWorked,
        uint64 activityDate
    ) external returns (uint256 id) {
        uint256 len = bytes(activity).length;
        require(len > 0 && len <= MAX_ACTIVITY_BYTES, "Activity must be 1-140 bytes");
        require(minutesWorked > 0 && minutesWorked <= MAX_MINUTES_PER_ENTRY, "Minutes must be 1-1440");

        if (activityDate == 0) activityDate = uint64(block.timestamp);
        require(activityDate <= block.timestamp + 1 days, "Date too far in the future");

        id = entries.length;
        entries.push(Entry({
            id: id,
            volunteer: msg.sender,
            activity: activity,
            minutesWorked: minutesWorked,
            activityDate: activityDate,
            submittedAt: uint64(block.timestamp),
            status: Status.Pending,
            reviewer: address(0),
            note: ""
        }));
        entryIdsOf[msg.sender].push(id);

        if (!known[msg.sender]) {
            known[msg.sender] = true;
            volunteers.push(msg.sender);
        }

        emit HoursLogged(id, msg.sender, minutesWorked, activity);
    }

    function cancel(uint256 id) external {
        Entry storage e = _entry(id);
        require(e.volunteer == msg.sender, "Not your entry");
        require(e.status == Status.Pending, "Not pending");
        e.status = Status.Cancelled;
        emit EntryCancelled(id, msg.sender);
    }

    // ----------------------------------------------------------------- verifiers

    function review(uint256 id, bool approve, string calldata note) external onlyVerifier {
        Entry storage e = _entry(id);
        require(e.status == Status.Pending, "Not pending");
        require(e.volunteer != msg.sender, "Cannot review own entry");
        require(bytes(note).length <= MAX_ACTIVITY_BYTES, "Note too long");

        e.reviewer = msg.sender;
        e.note = note;

        if (approve) {
            e.status = Status.Approved;
            approvedMinutes[e.volunteer] += e.minutesWorked;
            totalApprovedMinutes += e.minutesWorked;
        } else {
            e.status = Status.Rejected;
        }

        emit HoursReviewed(id, msg.sender, approve, note);
    }

    // --------------------------------------------------------------------- admin

    function setVerifier(address who, bool allowed) external onlyOwner {
        require(who != address(0), "Zero address");
        isVerifier[who] = allowed;
        emit VerifierSet(who, allowed);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
        isVerifier[newOwner] = true;
    }

    // --------------------------------------------------------------------- views

    function entryCount() external view returns (uint256) {
        return entries.length;
    }

    function getEntry(uint256 id) external view returns (Entry memory) {
        return _entry(id);
    }

    /// @notice Paged read, handy for the HTML front end.
    function getEntries(uint256 start, uint256 count) external view returns (Entry[] memory out) {
        uint256 total = entries.length;
        if (start >= total) return new Entry[](0);
        uint256 end = start + count;
        if (end > total) end = total;
        out = new Entry[](end - start);
        for (uint256 i = start; i < end; i++) {
            out[i - start] = entries[i];
        }
    }

    function getEntryIds(address volunteer) external view returns (uint256[] memory) {
        return entryIdsOf[volunteer];
    }

    function getVolunteers() external view returns (address[] memory) {
        return volunteers;
    }

    // ------------------------------------------------------------------ internal

    function _entry(uint256 id) private view returns (Entry storage) {
        require(id < entries.length, "No such entry");
        return entries[id];
    }
}
