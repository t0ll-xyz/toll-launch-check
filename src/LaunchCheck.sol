// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// Read side of ERC-8470 Token Launch Observations (only what a hook needs).
interface ILaunchObservationsReader {
    enum Lean { None, Clear, Careful, Against }

    function latestFinding(uint256 chainId, address token, address detector, bytes32 kind, uint64 param)
        external
        view
        returns (uint256 observationId, uint64 observedBlock, uint64 recordedAt, uint256 value, Lean lean);
}

/// @title LaunchCheck
/// @notice One view call a hook makes before a buy: did an independent detector see a bundled or
///         wallet-ring launch for this token? Reads block-pinned facts from an ERC-8470 registry and
///         compares them with limits the pool creator picks. No API, no oracle, no off-chain call.
/// @dev Shares are basis points of total supply (0..10000). A fact the detector has not written yet is
///      "not read" (type(uint256).max); it never counts as clean or dirty on its own, the policy decides
///      (`blockUnread`). On Robinhood Chain a fresh launch is not observed for its first ~20 minutes.
contract LaunchCheck {
    uint256 internal constant NOT_READ = type(uint256).max;

    bytes32 public constant FIRST_BLOCK_SHARE = keccak256("erc.launch-observations.first-block-share");
    bytes32 public constant FUNDING_LINKED_SHARE = keccak256("erc.launch-observations.funding-linked-share");

    /// Reasons returned by `check`.
    bytes32 public constant OK = "ok";
    bytes32 public constant NOT_OBSERVED = "not-observed";
    bytes32 public constant FIRST_BLOCK = "first-block-share";
    bytes32 public constant FUNDING_LINKED = "funding-linked-share";

    struct Policy {
        uint16 maxFirstBlockBps; // e.g. 2500: refuse when more than 25% of supply went in the first block. 0 = off
        uint16 maxFundingLinkedBps; // e.g. 2000: refuse when more than 20% sits with wallets sharing a funder. 0 = off
        bool blockUnread; // true: refuse until the detector has observed the token
    }

    ILaunchObservationsReader public immutable registry;
    address public immutable detector;

    constructor(ILaunchObservationsReader registry_, address detector_) {
        registry = registry_;
        detector = detector_;
    }

    /// @return allowed whether a buy passes the policy
    /// @return reason  OK, NOT_OBSERVED, FIRST_BLOCK or FUNDING_LINKED
    /// @return value   the share (bps) that tripped the limit, else 0
    function check(address token, Policy calldata p)
        external
        view
        returns (bool allowed, bytes32 reason, uint256 value)
    {
        (uint256 obsId,,, uint256 firstBlock,) =
            registry.latestFinding(block.chainid, token, detector, FIRST_BLOCK_SHARE, 0);
        if (obsId == 0) return (!p.blockUnread, NOT_OBSERVED, 0);

        if (p.maxFirstBlockBps != 0 && firstBlock != NOT_READ && firstBlock > p.maxFirstBlockBps) {
            return (false, FIRST_BLOCK, firstBlock);
        }
        if (p.maxFundingLinkedBps != 0) {
            (,,, uint256 linked,) = registry.latestFinding(block.chainid, token, detector, FUNDING_LINKED_SHARE, 1);
            if (linked != NOT_READ && linked > p.maxFundingLinkedBps) return (false, FUNDING_LINKED, linked);
        }
        return (true, OK, 0);
    }
}
