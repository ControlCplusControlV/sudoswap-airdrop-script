// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "forge-std/StdJson.sol";
import "../lib/solady/src/utils/MerkleProofLib.sol";
import "../src/SudooClaim.sol";

contract DeploySudooClaim is Script {
    using stdJson for string;

    struct ClaimData {
        address account;
        uint256 amount;
    }

    function run() external {
        // Read the distribution data from JSON
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/bera_airdrop_distributions.json");
        string memory json = vm.readFile(path);
        
        // Choose which distribution method to use (collection_based or volume_based)
        // You can change this to "distribution_by_volume" for volume-based distribution
        string memory distributionMethod = "distribution_by_collection";
        
        // Get all addresses from the chosen distribution
        string[] memory addressKeys = vm.parseJsonKeys(json, string.concat(".", distributionMethod));
        
        // Create arrays for merkle tree generation
        ClaimData[] memory claims = new ClaimData[](addressKeys.length);
        bytes32[] memory leaves = new bytes32[](addressKeys.length);
        
        uint256 validClaims = 0;
        for (uint256 i = 0; i < addressKeys.length; i++) {
            address addr = vm.parseAddress(addressKeys[i]);
            uint256 amount = vm.parseJsonUint(json, string.concat(".", distributionMethod, ".", addressKeys[i], ".allocation"));
            
            // Convert from BERA to wei (18 decimals)
            amount = amount * 1e18;
            
            if (amount > 0) {
                claims[validClaims] = ClaimData(addr, amount);
                leaves[validClaims] = keccak256(bytes.concat(keccak256(abi.encode(addr, amount))));
                validClaims++;
            }
        }
        
        // Trim arrays to valid claims
        assembly {
            mstore(claims, validClaims)
            mstore(leaves, validClaims)
        }
        
        // Generate merkle root
        bytes32 merkleRoot = generateMerkleRoot(leaves);
        
        console2.log("Merkle root:", vm.toString(merkleRoot));
        console2.log("Total claims:", validClaims);
        
        // Deploy configuration
        address beraToken = vm.envAddress("BERA_TOKEN_ADDRESS");
        address owner = vm.envOr("OWNER_ADDRESS", msg.sender);
        
        vm.startBroadcast();
        
        // Deploy the SudooClaim contract
        SudooClaim sudooClaim = new SudooClaim(
            beraToken,
            merkleRoot,
            owner
        );
        
        console2.log("SudooClaim deployed at:", address(sudooClaim));
        console2.log("Merkle root:", vm.toString(merkleRoot));
        console2.log("BERA token:", beraToken);
        console2.log("Owner:", owner);
        
        vm.stopBroadcast();
        
        // Save deployment info and merkle proofs
        saveDeploymentData(address(sudooClaim), merkleRoot, claims);
    }
    
    function generateMerkleRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        uint256 n = leaves.length;
        if (n == 0) return bytes32(0);
        if (n == 1) return leaves[0];
        
        // Create a copy of leaves for processing
        bytes32[] memory tree = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            tree[i] = leaves[i];
        }
        
        // Build the merkle tree
        uint256 currentN = n;
        while (currentN > 1) {
            uint256 nextN = (currentN + 1) / 2;
            for (uint256 i = 0; i < nextN; i++) {
                uint256 left = i * 2;
                uint256 right = left + 1;
                
                if (right < currentN) {
                    tree[i] = keccak256(abi.encodePacked(
                        tree[left] < tree[right] ? tree[left] : tree[right],
                        tree[left] < tree[right] ? tree[right] : tree[left]
                    ));
                } else {
                    tree[i] = tree[left];
                }
            }
            currentN = nextN;
        }
        
        return tree[0];
    }
    
    function generateMerkleProof(bytes32[] memory leaves, uint256 index) internal pure returns (bytes32[] memory) {
        uint256 n = leaves.length;
        require(index < n, "Invalid index");
        
        // Count proof elements needed
        uint256 proofLength = 0;
        uint256 pos = index;
        uint256 width = n;
        while (width > 1) {
            if (pos % 2 == 1 || pos + 1 < width) {
                proofLength++;
            }
            pos /= 2;
            width = (width + 1) / 2;
        }
        
        bytes32[] memory proof = new bytes32[](proofLength);
        uint256 proofIndex = 0;
        
        // Build the tree and extract proof
        bytes32[] memory tree = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            tree[i] = leaves[i];
        }
        
        pos = index;
        width = n;
        
        while (width > 1) {
            if (pos % 2 == 0) {
                if (pos + 1 < width) {
                    proof[proofIndex++] = tree[pos + 1];
                }
            } else {
                proof[proofIndex++] = tree[pos - 1];
            }
            
            // Build next level
            uint256 nextWidth = (width + 1) / 2;
            for (uint256 i = 0; i < nextWidth; i++) {
                uint256 left = i * 2;
                uint256 right = left + 1;
                
                if (right < width) {
                    tree[i] = keccak256(abi.encodePacked(
                        tree[left] < tree[right] ? tree[left] : tree[right],
                        tree[left] < tree[right] ? tree[right] : tree[left]
                    ));
                } else {
                    tree[i] = tree[left];
                }
            }
            
            pos /= 2;
            width = nextWidth;
        }
        
        return proof;
    }
    
    function saveDeploymentData(address sudooClaim, bytes32 merkleRoot, ClaimData[] memory claims) internal {
        // Generate merkle proofs for all claims
        bytes32[] memory leaves = new bytes32[](claims.length);
        for (uint256 i = 0; i < claims.length; i++) {
            leaves[i] = keccak256(bytes.concat(keccak256(abi.encode(claims[i].account, claims[i].amount))));
        }
        
        // Create deployment info JSON
        string memory obj = "deployment";
        vm.serializeAddress(obj, "sudooClaim", sudooClaim);
        vm.serializeBytes32(obj, "merkleRoot", merkleRoot);
        vm.serializeUint(obj, "totalClaims", claims.length);
        
        // Create proofs array
        string memory proofsObj = "proofs";
        for (uint256 i = 0; i < claims.length; i++) {
            bytes32[] memory proof = generateMerkleProof(leaves, i);
            
            string memory claimObj = vm.toString(claims[i].account);
            vm.serializeAddress(claimObj, "address", claims[i].account);
            vm.serializeUint(claimObj, "amount", claims[i].amount);
            vm.serializeBytes32(claimObj, "leaf", leaves[i]);
            string memory proofArray = vm.serializeBytes32(claimObj, "proof", proof);
            
            if (i == claims.length - 1) {
                vm.serializeString(proofsObj, vm.toString(claims[i].account), proofArray);
            } else {
                vm.serializeString(proofsObj, vm.toString(claims[i].account), proofArray);
            }
        }
        
        string memory finalJson = vm.serializeString(obj, "claims", proofsObj);
        vm.writeJson(finalJson, "./deployment_output.json");
        
        console2.log("Deployment data saved to deployment_output.json");
    }
}