// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../src/SudooClaim.sol";
import "../lib/solmate/src/tokens/ERC20.sol";

contract MockBERA is ERC20 {
    constructor() ERC20("BERA Token", "BERA", 18) {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract SudooClaimTest is Test {
    SudooClaim public sudooClaim;
    MockBERA public beraToken;
    
    address public owner = address(0x1337);
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    
    uint256 public aliceAmount = 1000 ether;
    uint256 public bobAmount = 2000 ether;
    uint256 public charlieAmount = 3000 ether;
    
    bytes32 public merkleRoot;
    bytes32[] public merkleProofAlice;
    bytes32[] public merkleProofBob;
    bytes32[] public merkleProofCharlie;
    
    function setUp() public {
        // Deploy mock BERA token
        beraToken = new MockBERA();
        
        // Generate merkle tree
        bytes32[] memory leaves = new bytes32[](3);
        leaves[0] = keccak256(bytes.concat(keccak256(abi.encode(alice, aliceAmount))));
        leaves[1] = keccak256(bytes.concat(keccak256(abi.encode(bob, bobAmount))));
        leaves[2] = keccak256(bytes.concat(keccak256(abi.encode(charlie, charlieAmount))));
        
        // Sort leaves for consistent merkle root
        for (uint i = 0; i < leaves.length - 1; i++) {
            for (uint j = 0; j < leaves.length - i - 1; j++) {
                if (leaves[j] > leaves[j + 1]) {
                    bytes32 temp = leaves[j];
                    leaves[j] = leaves[j + 1];
                    leaves[j + 1] = temp;
                }
            }
        }
        
        // Build proper merkle tree
        // For this test, let's create a simple tree with proper ordering
        
        // Create unsorted leaves first to match addresses
        bytes32 leafAlice = keccak256(bytes.concat(keccak256(abi.encode(alice, aliceAmount))));
        bytes32 leafBob = keccak256(bytes.concat(keccak256(abi.encode(bob, bobAmount))));
        bytes32 leafCharlie = keccak256(bytes.concat(keccak256(abi.encode(charlie, charlieAmount))));
        
        // For a proper merkle tree with 3 leaves:
        // Level 0: [leafAlice, leafBob, leafCharlie]
        // Level 1: [hash(leafAlice, leafBob), leafCharlie]
        // Level 2: [hash(hash(leafAlice, leafBob), leafCharlie)]
        
        bytes32 node01 = leafAlice < leafBob ? 
            keccak256(abi.encodePacked(leafAlice, leafBob)) : 
            keccak256(abi.encodePacked(leafBob, leafAlice));
            
        merkleRoot = node01 < leafCharlie ? 
            keccak256(abi.encodePacked(node01, leafCharlie)) : 
            keccak256(abi.encodePacked(leafCharlie, node01));
        
        // Generate proofs
        merkleProofAlice = new bytes32[](2);
        merkleProofAlice[0] = leafBob;
        merkleProofAlice[1] = leafCharlie;
        
        merkleProofBob = new bytes32[](2);
        merkleProofBob[0] = leafAlice;
        merkleProofBob[1] = leafCharlie;
        
        merkleProofCharlie = new bytes32[](1);
        merkleProofCharlie[0] = node01;
        
        // Deploy SudooClaim contract
        vm.prank(owner);
        sudooClaim = new SudooClaim(address(beraToken), merkleRoot, owner);
        
        // Fund the claim contract
        beraToken.mint(address(sudooClaim), aliceAmount + bobAmount + charlieAmount);
    }
    
    function testConstructor() public {
        assertEq(address(sudooClaim.beraToken()), address(beraToken));
        assertEq(sudooClaim.merkleRoot(), merkleRoot);
        assertEq(sudooClaim.owner(), owner);
    }
    
    function testValidClaim() public {
        // Alice claims
        vm.prank(alice);
        sudooClaim.claim(merkleProofAlice, aliceAmount);
        
        assertEq(beraToken.balanceOf(alice), aliceAmount);
        assertTrue(sudooClaim.claimed(alice));
    }
    
    function testMultipleClaims() public {
        // Alice claims
        vm.prank(alice);
        sudooClaim.claim(merkleProofAlice, aliceAmount);
        
        // Bob claims
        vm.prank(bob);
        sudooClaim.claim(merkleProofBob, bobAmount);
        
        // Charlie claims
        vm.prank(charlie);
        sudooClaim.claim(merkleProofCharlie, charlieAmount);
        
        assertEq(beraToken.balanceOf(alice), aliceAmount);
        assertEq(beraToken.balanceOf(bob), bobAmount);
        assertEq(beraToken.balanceOf(charlie), charlieAmount);
        
        assertTrue(sudooClaim.claimed(alice));
        assertTrue(sudooClaim.claimed(bob));
        assertTrue(sudooClaim.claimed(charlie));
    }
    
    function testCannotClaimTwice() public {
        // Alice claims
        vm.prank(alice);
        sudooClaim.claim(merkleProofAlice, aliceAmount);
        
        // Try to claim again
        vm.expectRevert(SudooClaim.AlreadyClaimed.selector);
        vm.prank(alice);
        sudooClaim.claim(merkleProofAlice, aliceAmount);
    }
    
    function testInvalidProof() public {
        // Try to claim with wrong proof
        bytes32[] memory wrongProof = new bytes32[](2);
        wrongProof[0] = bytes32(0);
        wrongProof[1] = bytes32(0);
        
        vm.expectRevert(SudooClaim.InvalidProof.selector);
        vm.prank(alice);
        sudooClaim.claim(wrongProof, aliceAmount);
    }
    
    function testInvalidAmount() public {
        // Try to claim wrong amount with valid proof
        vm.expectRevert(SudooClaim.InvalidProof.selector);
        vm.prank(alice);
        sudooClaim.claim(merkleProofAlice, aliceAmount + 1);
    }
    
    function testRescueTokens() public {
        // Deploy another token and send some to the contract
        MockBERA otherToken = new MockBERA();
        otherToken.mint(address(sudooClaim), 1000 ether);
        
        uint256 balanceBefore = otherToken.balanceOf(owner);
        
        // Owner rescues tokens
        vm.prank(owner);
        sudooClaim.rescueTokens(address(otherToken), owner, 1000 ether);
        
        assertEq(otherToken.balanceOf(owner), balanceBefore + 1000 ether);
        assertEq(otherToken.balanceOf(address(sudooClaim)), 0);
    }
    
    function testOnlyOwnerCanRescueTokens() public {
        // Non-owner tries to rescue
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(alice);
        sudooClaim.rescueTokens(address(beraToken), alice, 100 ether);
    }
    
    function testRescueEth() public {
        // Send ETH to contract
        vm.deal(address(sudooClaim), 1 ether);
        
        uint256 balanceBefore = owner.balance;
        
        // Owner rescues ETH
        vm.prank(owner);
        sudooClaim.rescueEth(owner);
        
        assertEq(owner.balance, balanceBefore + 1 ether);
        assertEq(address(sudooClaim).balance, 0);
    }
    
    function testOnlyOwnerCanRescueEth() public {
        // Send ETH to contract
        vm.deal(address(sudooClaim), 1 ether);
        
        // Non-owner tries to rescue
        vm.expectRevert("UNAUTHORIZED");
        vm.prank(alice);
        sudooClaim.rescueEth(alice);
    }
    
    function testReceiveEth() public {
        // Test that contract can receive ETH
        vm.deal(address(this), 1 ether);
        (bool success,) = address(sudooClaim).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(sudooClaim).balance, 1 ether);
    }
    
    function testFuzzClaim(address claimer, uint256 amount) public {
        // Bound the amount to reasonable values
        amount = bound(amount, 1, 1000000 ether);
        vm.assume(claimer != address(0));
        
        // Generate merkle root for this claim
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(claimer, amount))));
        bytes32 fuzzRoot = leaf; // Single leaf tree
        
        // Deploy new contract with this root
        SudooClaim fuzzClaim = new SudooClaim(address(beraToken), fuzzRoot, owner);
        beraToken.mint(address(fuzzClaim), amount);
        
        // Create empty proof for single leaf
        bytes32[] memory emptyProof = new bytes32[](0);
        
        // Claim should work
        vm.prank(claimer);
        fuzzClaim.claim(emptyProof, amount);
        
        assertEq(beraToken.balanceOf(claimer), amount);
        assertTrue(fuzzClaim.claimed(claimer));
    }
}