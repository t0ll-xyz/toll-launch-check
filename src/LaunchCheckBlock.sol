// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LaunchCheck} from "./LaunchCheck.sol";

/// @title LaunchCheckBlock
/// @notice Drop-in piece for a Uniswap v4 hook: call `_launchCheck(token)` in `beforeSwap` when the swap
///         buys `token`. A flagged buy reverts with the reason; sells always pass, so holders can exit.
///
/// In a v4-periphery BaseHook:
///
///     function _beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
///         internal override returns (bytes4, BeforeSwapDelta, uint24)
///     {
///         // launched token is currency1 here; zeroForOne == true means currency0 in, currency1 out: a buy
///         if (params.zeroForOne) _launchCheck(Currency.unwrap(key.currency1));
///         return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
///     }
abstract contract LaunchCheckBlock {
    error LaunchCheckRefused(address token, bytes32 reason, uint256 value);

    LaunchCheck public immutable launchCheck;
    LaunchCheck.Policy public policy;

    constructor(LaunchCheck launchCheck_, LaunchCheck.Policy memory policy_) {
        launchCheck = launchCheck_;
        policy = policy_;
    }

    function _launchCheck(address token) internal view {
        (bool ok, bytes32 reason, uint256 value) = launchCheck.check(token, policy);
        if (!ok) revert LaunchCheckRefused(token, reason, value);
    }
}
