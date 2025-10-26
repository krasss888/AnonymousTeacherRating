// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/* Zama official FHE library */
import { FHE, ebool, euint8, euint32, euint64, externalEuint8 } from "@fhevm/solidity/lib/FHE.sol";
/* Network config (Sepolia example; swap if you deploy elsewhere) */
import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

/**
 * @title AnonymousTeacherRating
 * @notice Students submit encrypted 1..5 ratings. Individual ratings remain private.
 *         Per-teacher aggregates (sum, count) are kept encrypted onchain but are
 *         marked as publicly decryptable so anyone can fetch plaintext via Relayer SDK.
 *
 *         IMPORTANT: We do NOT compute average onchain because division by an encrypted
 *         denominator is not supported (division expects a plaintext divisor). Consumers
 *         should public-decrypt (sum, count) and compute avg = sum / count offchain.
 */
contract AnonymousTeacherRating is SepoliaConfig {
    /* ─────────────────────────── Ownable ─────────────────────────── */
    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "Not owner"); _; }

    constructor() {
        owner = msg.sender;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero owner");
        owner = newOwner;
    }

    /* ────────────────────────── Teachers ─────────────────────────── */
    struct Aggregates {
        euint64 sum;   // sum of ratings
        euint32 count; // number of accepted ratings
        bool exists;
        string name;   // optional public metadata
    }

    mapping(uint256 => Aggregates) private _agg;

    event TeacherAdded(uint256 indexed teacherId, string name);
    event TeacherUpdated(uint256 indexed teacherId, string name);

    function addTeacher(uint256 teacherId, string calldata name) external onlyOwner {
        require(teacherId != 0, "teacherId=0 reserved");
        require(!_agg[teacherId].exists, "Already exists");
        Aggregates storage a = _agg[teacherId];
        a.sum   = FHE.asEuint64(0);
        a.count = FHE.asEuint32(0);
        a.exists = true;
        a.name = name;

        // Allow contract to keep using these ciphertexts across txs
        FHE.allowThis(a.sum);
        FHE.allowThis(a.count);

        // Make aggregates publicly decryptable from day one
        FHE.makePubliclyDecryptable(a.sum);
        FHE.makePubliclyDecryptable(a.count);

        emit TeacherAdded(teacherId, name);
    }

    function setTeacherName(uint256 teacherId, string calldata name) external onlyOwner {
        require(_agg[teacherId].exists, "No such teacher");
        _agg[teacherId].name = name;
        emit TeacherUpdated(teacherId, name);
    }

    /* ─────────────────── Encrypted rating submission ─────────────── */
    event RatingSubmitted(
        uint256 indexed teacherId,
        address indexed rater,
        bytes32 sumHandle,
        bytes32 countHandle
    );

    /**
     * @notice Submit an encrypted rating (1..5). Invalid inputs are safely ignored
     *         using encrypted branching (no revert on private conditions).
     * @param teacherId  Target teacher
     * @param ratingExt  externalEuint8 handle produced by the Relayer SDK
     * @param proof      attestation (ZKPoK signatures) from the coprocessors
     */
    function submitRating(
        uint256 teacherId,
        externalEuint8 ratingExt,
        bytes calldata proof
    ) external {
        require(_agg[teacherId].exists, "Teacher not found");
        require(proof.length > 0, "Empty proof");

        // Deserialize external value (verifies attestation internally)
        euint8 r = FHE.fromExternal(ratingExt, proof);

        // Validate 1..5 privately: ok = (r >= 1) && (r <= 5)
        ebool ge1 = FHE.ge(r, FHE.asEuint8(1));
        ebool le5 = FHE.le(r, FHE.asEuint8(5));
        ebool ok  = FHE.and(ge1, le5);

        // Conditionally add to sum and count; if invalid, add 0
        Aggregates storage a = _agg[teacherId];

        // sum += (ok ? r : 0)
        euint64 addSum = FHE.select(ok, FHE.asEuint64(r), FHE.asEuint64(0));
        a.sum = FHE.add(a.sum, addSum);

        // count += (ok ? 1 : 0)
        euint32 addCnt = FHE.select(ok, FHE.asEuint32(1), FHE.asEuint32(0));
        a.count = FHE.add(a.count, addCnt);

        // Re-allow contract to use updated ciphertexts later
        FHE.allowThis(a.sum);
        FHE.allowThis(a.count);

        // Make aggregates publicly decryptable so anyone can fetch plaintext via Gateway
        FHE.makePubliclyDecryptable(a.sum);
        FHE.makePubliclyDecryptable(a.count);

        // (Optional) allow sender to userDecrypt if you want a personal UX
        // FHE.allow(a.sum, msg.sender);
        // FHE.allow(a.count, msg.sender);

        emit RatingSubmitted(teacherId, msg.sender, FHE.toBytes32(a.sum), FHE.toBytes32(a.count));
    }

    /* ─────────────────────── Read APIs (view) ────────────────────── */

    function version() external pure returns (string memory) {
        return "AnonymousTeacherRating/1.0.0";
    }

    function teacherExists(uint256 teacherId) external view returns (bool) {
        return _agg[teacherId].exists;
    }

    function teacherName(uint256 teacherId) external view returns (string memory) {
        require(_agg[teacherId].exists, "No such teacher");
        return _agg[teacherId].name;
    }

    /** Encrypted handles: usable with Relayer SDK (publicDecrypt / userDecrypt). */
    function getAggregates(uint256 teacherId) external view returns (euint64 sumCt, euint32 countCt) {
        require(_agg[teacherId].exists, "No such teacher");
        return (_agg[teacherId].sum, _agg[teacherId].count);
    }

    /** Convenience: raw bytes32 handles for straight relayer calls. */
    function getAggregateHandles(uint256 teacherId) external view returns (bytes32 sumH, bytes32 countH) {
        require(_agg[teacherId].exists, "No such teacher");
        sumH = FHE.toBytes32(_agg[teacherId].sum);
        countH = FHE.toBytes32(_agg[teacherId].count);
    }

    /**
     * @notice Re-mark aggregates as public if needed (e.g., after migrations).
     *         Anyone can call; it only affects decryptability flags.
     */
    function ensurePublic(uint256 teacherId) external {
        require(_agg[teacherId].exists, "No such teacher");
        FHE.makePubliclyDecryptable(_agg[teacherId].sum);
        FHE.makePubliclyDecryptable(_agg[teacherId].count);
    }
}
