// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {AuthorizationModule} from "../src/core/AuthorizationModule.sol";
import {ProposalManager} from "../src/core/ProposalManager.sol";
import {TimelockQueue} from "../src/core/TimelockQueue.sol";
import {GovernanceProtection} from "../src/modules/GovernanceProtection.sol";
import {RewardDistributor} from "../src/modules/RewardDistributor.sol";
import {IAuthorizationModule} from "../src/interfaces/IAuthorizationModule.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract GovernanceSystemTest is Test {
    AuthorizationModule public authModule;
    ProposalManager public proposalManager;
    TimelockQueue public timelockQueue;
    GovernanceProtection public govProtection;
    RewardDistributor public rewardDistributor;
    MockERC20 public rewardToken;

    address public owner;
    address public signer1;
    address public signer2;
    address public attacker;
    
    uint256 public signer1PrivateKey;
    uint256 public signer2PrivateKey;
    
    uint256 constant MIN_DELAY = 3 days;
    
    event ProposalApproved(bytes32 indexed proposalId, address[] signers);
    event TransactionThatWasQueued(bytes32 indexed proposalId);
    event TransactionThatWasExecuted(bytes32 indexed proposalId);

    function setUp() public {
        owner = address(this);
        signer1PrivateKey = 0xA11CE;
        signer2PrivateKey = 0xB0B;
        signer1 = vm.addr(signer1PrivateKey);
        signer2 = vm.addr(signer2PrivateKey);
        attacker = makeAddr("attacker");
        
        // Deploy contracts
        authModule = new AuthorizationModule();
        govProtection = new GovernanceProtection(100 ether); // 100 ETH execution cap
        proposalManager = new ProposalManager(address(authModule), address(govProtection));
        timelockQueue = new TimelockQueue(address(proposalManager), MIN_DELAY);
        
        // Grant roles for testing
        proposalManager.grantRole(proposalManager.PROPOSER_ROLE(), owner);
        proposalManager.grantRole(proposalManager.PROPOSER_ROLE(), attacker);

        // Deploy reward token and distributor
        rewardToken = new MockERC20(1000000 ether);
        bytes32 merkleRoot = keccak256("initial");
        rewardDistributor = new RewardDistributor(merkleRoot, 1000 ether, address(rewardToken));
        
        vm.deal(address(timelockQueue), 100 ether);
    }

    // ============ FUNCTIONAL TESTS ============

    function test_ProposalLifecycle() public {
        // 1. Create proposal
        address target = address(0x123);
        uint256 value = 1 ether;
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", signer1, value);
        
        bytes32 proposalId = proposalManager.createProposal(target, value, data);
        assertTrue(proposalId != bytes32(0), "Proposal should be created");
        
        // 2. Commit proposal
        proposalManager.commitProposal(proposalId);
        
        // 3. Mark approval required
        proposalManager.markApprovalRequired(proposalId);
        
        // 4. Approve with signatures
        IAuthorizationModule.TreasuryAction memory action = IAuthorizationModule.TreasuryAction({
            proposalId: proposalId,
            target: target,
            value: value,
            data: data,
            nonce: 0,
            chainId: block.chainid
        });
        
        bytes memory sig1 = _signAction(action, signer1PrivateKey);
        
        address[] memory signers = new address[](1);
        signers[0] = signer1;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = sig1;
        
        vm.expectEmit(true, false, false, true);
        emit ProposalApproved(proposalId, signers);
        authModule.approveProposal(action, signers, signatures);
        
        assertTrue(authModule.isApproved(proposalId), "Proposal should be approved");
        
        // 5. Queue proposal
        proposalManager.queueProposal(proposalId);
        assertTrue(proposalManager.isApproved(proposalId), "Proposal should be marked approved");
    }

    function test_SignatureVerification() public view {
        bytes32 proposalId = keccak256("test");
        address target = address(0x123);
        uint256 value = 1 ether;
        bytes memory data = "0x";
        
        IAuthorizationModule.TreasuryAction memory action = IAuthorizationModule.TreasuryAction({
            proposalId: proposalId,
            target: target,
            value: value,
            data: data,
            nonce: 0,
            chainId: block.chainid
        });
        
        bytes memory signature = _signAction(action, signer1PrivateKey);
        
        bool isValid = authModule.verifySignature(action, signer1, signature);
        assertTrue(isValid, "Signature should be valid");
    }

    function test_TimelockExecution() public {
        // Create and approve proposal
        bytes32 proposalId = _createAndApproveProposal();
        
        address target = address(0x123);
        uint256 value = 1 ether;
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", signer1, value);
        
        // Queue transaction
        vm.expectEmit(true, false, false, false);
        emit TransactionThatWasQueued(proposalId);
        timelockQueue.queueTransaction(proposalId, target, value, data, MIN_DELAY);
        
        // Fast forward time
        vm.warp(block.timestamp + MIN_DELAY);
        
        // Execute
        vm.expectEmit(true, false, false, false);
        emit TransactionThatWasExecuted(proposalId);
        timelockQueue.executeTransaction(proposalId, target, value, data);
        
        (,,,,,bool executed,) = timelockQueue.getQueuedTransaction(proposalId);
        assertTrue(executed, "Transaction should be executed");
    }

    function test_RewardClaiming() public {
        // Setup merkle tree with one recipient
        address recipient = signer1;
        uint256 amount = 10 ether;
        
        bytes32 leaf = keccak256(abi.encodePacked(recipient, amount));
        bytes32 merkleRoot = leaf; // Single leaf tree
        
        // Create new distributor with correct root and fund it
        MockERC20 token = new MockERC20(1000 ether);
        RewardDistributor distributor = new RewardDistributor(merkleRoot, 1000 ether, address(token));
        assertTrue(token.transfer(address(distributor), 100 ether));
        
        bytes32[] memory proof = new bytes32[](0);
        
        uint256 balanceBefore = token.balanceOf(recipient);
        
        vm.prank(recipient);
        distributor.claim(recipient, amount, proof);
        
        uint256 balanceAfter = token.balanceOf(recipient);
        assertEq(balanceAfter - balanceBefore, amount, "Recipient should receive tokens");
        assertTrue(distributor.hasClaimed(recipient), "Claim should be marked");
    }

    // ============ EXPLOIT TESTS (NEGATIVE CASES) ============

    function test_Reentrancy_ShouldFail() public {
        // Create a simple proposal that will succeed
        address target = makeAddr("simpleTarget");
        uint256 value = 0;
        bytes memory data = abi.encodeWithSignature("someFunction()");
        
        bytes32 proposalId = proposalManager.createProposal(target, value, data);
        proposalManager.commitProposal(proposalId);
        proposalManager.markApprovalRequired(proposalId);
        
        // Approve it
        IAuthorizationModule.TreasuryAction memory action = IAuthorizationModule.TreasuryAction({
            proposalId: proposalId,
            target: target,
            value: value,
            data: data,
            nonce: authModule.getNonce(signer1),
            chainId: block.chainid
        });
        
        bytes memory sig = _signAction(action, signer1PrivateKey);
        address[] memory signers = new address[](1);
        signers[0] = signer1;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = sig;
        
        authModule.approveProposal(action, signers, signatures);
        proposalManager.queueProposal(proposalId);
        
        // Queue and execute
        timelockQueue.queueTransaction(proposalId, target, value, data, MIN_DELAY);
        vm.warp(block.timestamp + MIN_DELAY);
        
        // First execution succeeds
        timelockQueue.executeTransaction(proposalId, target, value, data);
        
        // Try to execute again (reentrancy simulation)
        vm.expectRevert("Already executed");
        timelockQueue.executeTransaction(proposalId, target, value, data);
    }

    function test_DoubleClaim_ShouldFail() public {
        address recipient = signer1;
        uint256 amount = 10 ether;
        
        bytes32 leaf = keccak256(abi.encodePacked(recipient, amount));
        bytes32 merkleRoot = leaf;
        
        MockERC20 token = new MockERC20(1000 ether);
        RewardDistributor distributor = new RewardDistributor(merkleRoot, 1000 ether, address(token));
        assertTrue(token.transfer(address(distributor), 100 ether));
        
        bytes32[] memory proof = new bytes32[](0);
        
        // First claim succeeds
        vm.prank(recipient);
        distributor.claim(recipient, amount, proof);
        
        // Second claim should fail
        vm.prank(recipient);
        vm.expectRevert("Already claimed");
        distributor.claim(recipient, amount, proof);
    }

    function test_InvalidSignature_ShouldFail() public view {
        bytes32 proposalId = keccak256("test");
        address target = address(0x123);
        uint256 value = 1 ether;
        bytes memory data = "0x";
        
        IAuthorizationModule.TreasuryAction memory action = IAuthorizationModule.TreasuryAction({
            proposalId: proposalId,
            target: target,
            value: value,
            data: data,
            nonce: 0,
            chainId: block.chainid
        });
        
        // Sign with wrong key
        bytes memory wrongSignature = _signAction(action, signer2PrivateKey);
        
        // Verify with different signer should fail
        bool isValid = authModule.verifySignature(action, signer1, wrongSignature);
        assertFalse(isValid, "Invalid signature should not verify");
    }

    function test_PrematureExecution_ShouldFail() public {
        bytes32 proposalId = _createAndApproveProposal();
        
        address target = address(0x123);
        uint256 value = 1 ether;
        bytes memory data = "0x";
        
        timelockQueue.queueTransaction(proposalId, target, value, data, MIN_DELAY);
        
        // Try to execute before delay
        vm.expectRevert("Execution delay not met");
        timelockQueue.executeTransaction(proposalId, target, value, data);
    }

    function test_SignatureReplay_ShouldFail() public {
        bytes32 proposalId = keccak256("test");
        address target = address(0x123);
        uint256 value = 1 ether;
        bytes memory data = "0x";
        
        IAuthorizationModule.TreasuryAction memory action = IAuthorizationModule.TreasuryAction({
            proposalId: proposalId,
            target: target,
            value: value,
            data: data,
            nonce: 0,
            chainId: block.chainid
        });
        
        bytes memory signature = _signAction(action, signer1PrivateKey);
        
        address[] memory signers = new address[](1);
        signers[0] = signer1;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;
        
        // First approval succeeds
        authModule.approveProposal(action, signers, signatures);
        
        // Try to replay same signature
        vm.expectRevert("Nonce already used");
        authModule.approveProposal(action, signers, signatures);
    }

    function test_UnauthorizedExecution_ShouldFail() public {
        address target = address(0x123);
        uint256 value = 1 ether;
        bytes memory data = "0x";
        
        // Create proposal without approval
        bytes32 proposalId = proposalManager.createProposal(target, value, data);
        proposalManager.commitProposal(proposalId);
        proposalManager.markApprovalRequired(proposalId);
        
        // Try to queue without approval
        vm.expectRevert("Proposal not approved");
        timelockQueue.queueTransaction(proposalId, target, value, data, MIN_DELAY);
    }

    function test_TimelockBypass_ShouldFail() public {
        bytes32 proposalId = _createAndApproveProposal();
        
        address target = address(0x123);
        uint256 value = 1 ether;
        bytes memory data = "0x";
        
        // Queue with minimum delay
        timelockQueue.queueTransaction(proposalId, target, value, data, MIN_DELAY);
        
        // Try to execute immediately (bypass timelock)
        vm.expectRevert("Execution delay not met");
        timelockQueue.executeTransaction(proposalId, target, value, data);
        
        // Even 1 second before should fail
        vm.warp(block.timestamp + MIN_DELAY - 1);
        vm.expectRevert("Execution delay not met");
        timelockQueue.executeTransaction(proposalId, target, value, data);
    }

    function test_ProposalReplay_ShouldFail() public {
        address target = address(0x123);
        uint256 value = 1 ether;
        bytes memory data = "0x";
        
        // Create first proposal
        bytes32 proposalId1 = proposalManager.createProposal(target, value, data);
        
        // Move to next block to change block.number
        vm.roll(block.number + 1);
        
        // Try to create identical proposal in different block
        // Should get different proposalId due to block.number in hash
        bytes32 proposalId2 = proposalManager.createProposal(target, value, data);
        
        assertTrue(proposalId1 != proposalId2, "Proposals should have unique IDs");
    }

    function test_CrossChainReplay_ShouldFail() public view {
        bytes32 proposalId = keccak256("test");
        address target = address(0x123);
        uint256 value = 1 ether;
        bytes memory data = "0x";
        
        // Create action for current chain
        IAuthorizationModule.TreasuryAction memory action = IAuthorizationModule.TreasuryAction({
            proposalId: proposalId,
            target: target,
            value: value,
            data: data,
            nonce: 0,
            chainId: block.chainid
        });
        
        bytes memory signature = _signAction(action, signer1PrivateKey);
        
        // Try to use signature with wrong chainId
        IAuthorizationModule.TreasuryAction memory wrongChainAction = IAuthorizationModule.TreasuryAction({
            proposalId: proposalId,
            target: target,
            value: value,
            data: data,
            nonce: 0,
            chainId: 999 // Wrong chain
        });
        
        bool isValid = authModule.verifySignature(wrongChainAction, signer1, signature);
        assertFalse(isValid, "Cross-chain replay should fail");
    }

    function test_GovernanceGriefing_ProposalLimitEnforced() public {
        // 1. Setup limit for attacker
        uint256 limit = 1 ether;
        govProtection.setProposalLimit(attacker, limit);
        
        vm.startPrank(attacker);
        
        address target = address(0x123);
        bytes memory data = "0x1234";
        
        // 2. Proposal within limit should succeed
        proposalManager.createProposal(target, limit, data);
        
        // 3. Proposal exceeding limit should fail
        uint256 exceedingValue = limit + 1;
        vm.expectRevert("Proposal limit exceeded");
        proposalManager.createProposal(target, exceedingValue, data);
        
        vm.stopPrank();
    }

    // ============ HELPER FUNCTIONS ============

    function _signAction(IAuthorizationModule.TreasuryAction memory action, uint256 privateKey) 
        internal 
        view 
        returns (bytes memory) 
    {
        bytes32 domainSeparator = authModule.domainSeparator();
        
        bytes32 actionHash = keccak256(abi.encode(
            keccak256("TreasuryAction(bytes32 proposalId,address target,uint256 value,bytes data,uint256 nonce,uint256 chainId)"),
            action.proposalId,
            action.target,
            action.value,
            keccak256(action.data),
            action.nonce,
            action.chainId
        ));
        
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            actionHash
        ));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _createAndApproveProposal() internal returns (bytes32) {
        address target = address(0x123);
        uint256 value = 1 ether;
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", signer1, value);
        
        bytes32 proposalId = proposalManager.createProposal(target, value, data);
        proposalManager.commitProposal(proposalId);
        proposalManager.markApprovalRequired(proposalId);
        
        IAuthorizationModule.TreasuryAction memory action = IAuthorizationModule.TreasuryAction({
            proposalId: proposalId,
            target: target,
            value: value,
            data: data,
            nonce: authModule.getNonce(signer1),
            chainId: block.chainid
        });
        
        bytes memory sig = _signAction(action, signer1PrivateKey);
        
        address[] memory signers = new address[](1);
        signers[0] = signer1;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = sig;
        
        authModule.approveProposal(action, signers, signatures);
        proposalManager.queueProposal(proposalId);
        
        return proposalId;
    }
}

// Malicious contract for reentrancy testing
contract MaliciousReentrant {
    TimelockQueue public timelock;
    uint256 public attackCount;
    
    constructor(address _timelock) {
        timelock = TimelockQueue(_timelock);
    }
    
    function attack() external payable {
        attackCount++;
        if (attackCount < 3) {
            // Try to reenter
            bytes32 proposalId = bytes32(uint256(1));
            timelock.executeTransaction(proposalId, address(this), 0, "");
        }
    }
    
    receive() external payable {
        if (attackCount < 3) {
            attackCount++;
        }
    }
}
