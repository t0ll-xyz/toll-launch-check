// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LaunchCheck, ILaunchObservationsReader} from "../src/LaunchCheck.sol";
import {LaunchCheckBlock} from "../src/LaunchCheckBlock.sol";

interface Vm {
    function createSelectFork(string calldata urlOrAlias, uint256 blockNumber) external returns (uint256);
    function expectRevert(bytes calldata) external;
}

contract DemoHook is LaunchCheckBlock {
    constructor(LaunchCheck c, LaunchCheck.Policy memory p) LaunchCheckBlock(c, p) {}

    function buy(address token) external view returns (bool) {
        _launchCheck(token);
        return true;
    }
}

/// Runs against the live ERC-8470 registry on Robinhood Chain (4663) and Toll's detector.
contract LaunchCheckForkTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    ILaunchObservationsReader constant REGISTRY =
        ILaunchObservationsReader(0x730E3C356299c9203cB042F6C0A9274aeABf9AF3);
    address constant DETECTOR = 0x02593AbFf31f4E8eC1D5c2F297a347C51ef06E5c;

    // observation 73: 33.56% of supply bought in the first block
    address constant BUNDLED = 0x4Ad0d62059eE0F4A5D7483E81B82fF40c4a7091C;
    // observation 77: 2.09% first block, 0% funding-linked
    address constant CLEAN = 0x4EC65c12f4a02cf4A4A4a9843a2e995A42215Eae;
    address constant UNSEEN = address(0xdead);

    LaunchCheck check;
    LaunchCheck.Policy policy;

    function setUp() public {
        vm.createSelectFork("rh", 103924809);
        check = new LaunchCheck(REGISTRY, DETECTOR);
        policy = LaunchCheck.Policy({maxFirstBlockBps: 2500, maxFundingLinkedBps: 2000, blockUnread: false});
    }

    function test_bundled_launch_refused() public view {
        (bool ok, bytes32 reason, uint256 value) = check.check(BUNDLED, policy);
        require(!ok && reason == check.FIRST_BLOCK() && value == 3356, "bundled should be refused at 3356 bps");
    }

    function test_clean_launch_allowed() public view {
        (bool ok, bytes32 reason,) = check.check(CLEAN, policy);
        require(ok && reason == check.OK(), "clean should pass");
    }

    function test_unseen_token_follows_policy() public view {
        (bool ok, bytes32 reason,) = check.check(UNSEEN, policy);
        require(ok && reason == check.NOT_OBSERVED(), "unseen passes when blockUnread=false");
        (ok,,) = check.check(UNSEEN, LaunchCheck.Policy(2500, 2000, true));
        require(!ok, "unseen refused when blockUnread=true");
    }

    function test_limit_off_allows_bundled() public view {
        (bool ok,,) = check.check(BUNDLED, LaunchCheck.Policy(0, 2000, false));
        require(ok, "first-block limit 0 = off");
    }

    function test_hook_reverts_buy_with_reason() public {
        DemoHook hook = new DemoHook(check, policy);
        require(hook.buy(CLEAN), "clean buy");
        vm.expectRevert(
            abi.encodeWithSelector(
                LaunchCheckBlock.LaunchCheckRefused.selector, BUNDLED, bytes32("first-block-share"), uint256(3356)
            )
        );
        hook.buy(BUNDLED);
    }
}
