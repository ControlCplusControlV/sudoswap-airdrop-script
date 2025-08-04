// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import { MerkleProofLib } from "../lib/solady/src/utils/MerkleProofLib.sol";
import { Owned } from "../lib/solmate/src/auth/Owned.sol";
import { ERC20 } from "../lib/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "../lib/solmate/src/utils/SafeTransferLib.sol";

/// @title SudooClaim
/// @author CopyPaste
/// @notice A merkle claim contract for BERA token distribution
contract SudooClaim is Owned {
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice The BERA token to be distributed
    ERC20 public immutable beraToken;
    
    /// @notice Merkle root for the claim distribution
    bytes32 public immutable merkleRoot;
    
    /// @notice Mapping to track claimed addresses
    mapping(address user => bool hasClaimed) public claimed;
    
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Emitted when tokens are claimed
    event Claimed(address indexed claimant, uint256 amount);
    
    /// @notice Emitted when tokens are rescued
    event TokensRescued(address indexed token, address indexed to, uint256 amount);
    
    /// @notice Emitted when ETH/BERA is rescued
    event EthRescued(address indexed to, uint256 amount);
    
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error AlreadyClaimed();
    error InvalidProof();
    error TransferFailed();
    
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Creates a new SudooClaim contract
    /// @param _beraToken The BERA token address
    /// @param _merkleRoot The merkle root for the distribution
    /// @param _owner The owner of the contract
    constructor(
        address _beraToken,
        bytes32 _merkleRoot,
        address _owner
    ) Owned(_owner) {
        beraToken = ERC20(_beraToken);
        merkleRoot = _merkleRoot;
    }
    
    /*//////////////////////////////////////////////////////////////
                            CLAIM FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Claim tokens using merkle proof
    /// @param proof The merkle proof for the claim
    /// @param amount The amount of tokens to claim
    function claim(bytes32[] calldata proof, uint256 amount) external {
        // Check if already claimed
        if (claimed[msg.sender]) revert AlreadyClaimed();
        
        // Verify merkle proof
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, amount))));
        if (!MerkleProofLib.verifyCalldata(proof, merkleRoot, leaf)) revert InvalidProof();
        
        // Mark as claimed
        claimed[msg.sender] = true;
        
        // Transfer tokens
        beraToken.safeTransfer(msg.sender, amount);
        
        emit Claimed(msg.sender, amount);
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Rescue any ERC20 tokens sent to this contract
    /// @param token The token to rescue
    /// @param to The address to send the tokens to
    /// @param amount The amount of tokens to rescue
    function rescueTokens(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        ERC20(token).safeTransfer(to, amount);
        emit TokensRescued(token, to, amount);
    }
    
    /// @notice Rescue ETH/BERA sent to this contract
    /// @param to The address to send the ETH/BERA to
    function rescueEth(address to) external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success, ) = to.call{value: balance}("");
        if (!success) revert TransferFailed();
        emit EthRescued(to, balance);
    }
    
    /// @notice Allow contract to receive ETH/BERA
    receive() external payable {}
}