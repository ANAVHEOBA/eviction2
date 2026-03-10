// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {AuthorizationModule} from "../src/core/AuthorizationModule.sol";
import {GovernanceProtection} from "../src/modules/GovernanceProtection.sol";
import {ProposalManager} from "../src/core/ProposalManager.sol";
import {TimelockQueue} from "../src/core/TimelockQueue.sol";
import {RewardDistributor} from "../src/modules/RewardDistributor.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy core modules
        console2.log("Deploying AuthorizationModule...");
        AuthorizationModule authModule = new AuthorizationModule();
        console2.log("AuthorizationModule deployed at:", address(authModule));
        
        console2.log("Deploying GovernanceProtection...");
        uint256 executionCap = 100 ether; // 100 ETH max per transaction
        GovernanceProtection govProtection = new GovernanceProtection(executionCap);
        console2.log("GovernanceProtection deployed at:", address(govProtection));
        
        console2.log("Deploying ProposalManager...");
        ProposalManager proposalManager = new ProposalManager(
            address(authModule),
            address(govProtection)
        );
        console2.log("ProposalManager deployed at:", address(proposalManager));
        
        console2.log("Deploying TimelockQueue...");
        uint256 minDelay = 3 days;
        TimelockQueue timelockQueue = new TimelockQueue(
            address(proposalManager),
            minDelay
        );
        console2.log("TimelockQueue deployed at:", address(timelockQueue));
        
        console2.log("Deploying RewardDistributor...");
        bytes32 initialMerkleRoot = bytes32(0); // Update with actual root
        uint256 totalAllocation = 1000000 ether; // 1M tokens
        address rewardToken = vm.envAddress("REWARD_TOKEN_ADDRESS");
        
        RewardDistributor rewardDistributor = new RewardDistributor(
            initialMerkleRoot,
            totalAllocation,
            rewardToken
        );
        console2.log("RewardDistributor deployed at:", address(rewardDistributor));
        
        vm.stopBroadcast();
        
        // Log deployment summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("AuthorizationModule:", address(authModule));
        console2.log("GovernanceProtection:", address(govProtection));
        console2.log("ProposalManager:", address(proposalManager));
        console2.log("TimelockQueue:", address(timelockQueue));
        console2.log("RewardDistributor:", address(rewardDistributor));
        console2.log("\nConfiguration:");
        console2.log("- Execution Cap:", executionCap);
        console2.log("- Min Delay:", minDelay);
        console2.log("- Total Allocation:", totalAllocation);
    }
}
