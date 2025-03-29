// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TheiaCrossChainManager
 * @dev Manages cross-chain functionality for THEIA token
 * Note: This is a simplified implementation. In production, you would use 
 * established cross-chain messaging protocols like LayerZero, Axelar, or Hyperlane
 */
contract TheiaCrossChainManager is AccessControl, ReentrancyGuard {
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    // Supported chains
    enum Chain {
        Polygon,
        Optimism,
        Avalanche
    }

    // Reference to THEIA token on this chain
    address public theiaToken;
    
    // Cross-chain token lock tracking
    struct CrossChainLock {
        Chain sourceChain;
        Chain targetChain;
        address user;
        uint256 amount;
        uint256 timestamp;
        bytes32 txHash;
        bool claimed;
    }
    
    // Mappings to track cross-chain operations
    mapping(bytes32 => CrossChainLock) public crossChainLocks;
    mapping(Chain => address) public chainToContract;
    mapping(Chain => uint256) public chainToNonce;

    // Events
    event TokensLocked(
        Chain indexed sourceChain,
        Chain indexed targetChain,
        address indexed user,
        uint256 amount,
        bytes32 lockId
    );

    event TokensUnlocked(
        Chain indexed sourceChain,
        Chain indexed targetChain,
        address indexed user,
        uint256 amount,
        bytes32 lockId
    );

    event ChainContractUpdated(Chain indexed chain, address contractAddress);
    
    /**
     * @dev Constructor 
     * @param _theiaToken Address of the THEIA token on this chain
     */
     constructor(address _theiaToken) {
        theiaToken = _theiaToken;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(BRIDGE_ROLE, msg.sender);
    }

    /**
     * @dev Updates the contract address for a specific chain
     * @param chain The chain enum value
     * @param contractAddress The address of the THEIA contract on that chain
     */
    function updateChainContract(Chain chain, address contractAddress) 
        external onlyRole(ADMIN_ROLE) 
    {
        chainToContract[chain] = contractAddress;
        emit ChainContractUpdated(chain, contractAddress);
    }

    /**
     * @dev Locks tokens on the source chain to be minted on the target chain
     * @param targetChain The destination chain
     * @param amount The amount of tokens to bridge
     * @return lockId Unique identifier for this cross-chain operation
     */
    function lockTokensForBridge(Chain targetChain, uint256 amount) 
        external nonReentrant returns (bytes32 lockId) 
    {
        require(amount > 0, "Amount must be greater than 0");
        require(chainToContract[targetChain] != address(0), "Target chain not supported");
        
        // Determine current chain (this would be implemented differently in production)
        Chain sourceChain = getCurrentChain();
        
        // Transfer tokens to this contract
        IERC20(theiaToken).transferFrom(msg.sender, address(this), amount);
        
        // Generate a unique lock ID
        chainToNonce[sourceChain]++;
        lockId = keccak256(abi.encodePacked(
            sourceChain,
            targetChain,
            msg.sender,
            amount,
            chainToNonce[sourceChain],
            block.timestamp
        ));

        // Record the lock
        crossChainLocks[lockId] = CrossChainLock({
            sourceChain: sourceChain,
            targetChain: targetChain,
            user: msg.sender,
            amount: amount,
            timestamp: block.timestamp,
            txHash: bytes32(0), // This would be filled by the relayer in production
            claimed: false
        });
        
        emit TokensLocked(sourceChain, targetChain, msg.sender, amount, lockId);
        
        // In a production environment, this would trigger an event that a relayer would pick up
        // to initiate the minting on the target chain
        
        return lockId;
    }

    /**
     * @dev Called by the bridge relayer to mint tokens on the target chain
     * @param sourceChain The chain where tokens were locked
     * @param user The user to receive the tokens
     * @param amount The amount of tokens to mint
     * @param lockId The unique lock ID from the source chain
     * @param proof Proof of the lock on the source chain (simplified here)
     */
    function unlockTokens(
        Chain sourceChain, 
        address user, 
        uint256 amount, 
        bytes32 lockId,
        bytes calldata proof
    ) external onlyRole(BRIDGE_ROLE) nonReentrant {
        // In production, this would verify the proof cryptographically
        // using signatures or Merkle proofs from validators
        
        // Simple check to prevent replay attacks
        require(!crossChainLocks[lockId].claimed, "Already claimed");
        
        // Mark as claimed
        crossChainLocks[lockId] = CrossChainLock({
            sourceChain: sourceChain,
            targetChain: getCurrentChain(),
            user: user,
            amount: amount,
            timestamp: block.timestamp,
            txHash: bytes32(0),
            claimed: true
        });

        // In production, this would call a function on the THEIA token contract
        // to mint the appropriate amount to the user
        // For simplicity, we'll just transfer from a reserve here
        IERC20(theiaToken).transfer(user, amount);
        
        emit TokensUnlocked(
            sourceChain, 
            getCurrentChain(), 
            user, 
            amount, 
            lockId
        );
    }

    /**
     * @dev Helper function to determine the current chain
     * @return The current chain enum value
     */
    function getCurrentChain() public view returns (Chain) {
        // In a real implementation, this would use chain-specific information
        // like chainId or other chain-specific values
        
        // For demonstration, we'll return Polygon by default
        return Chain.Polygon;
    }
    
    /**
     * @dev Get the contract address for a specific chain
     * @param chain The chain to query
     * @return The contract address on that chain
     */
    function getChainContract(Chain chain) external view returns (address) {
        return chainToContract[chain];
    }
    
    /**
     * @dev Get the current nonce for a specific chain
     * @param chain The chain to query
     * @return The current nonce
     */
    function getChainNonce(Chain chain) external view returns (uint256) {
        return chainToNonce[chain];
    }

    /**
     * @dev Get lock details by lock ID
     * @param lockId The lock ID to query
     * @return Lock details
     */
    function getLockDetails(bytes32 lockId) external view returns (
        Chain sourceChain,
        Chain targetChain,
        address user,
        uint256 amount,
        uint256 timestamp,
        bytes32 txHash,
        bool claimed
    ) {
        CrossChainLock memory lock = crossChainLocks[lockId];
        return (
            lock.sourceChain,
            lock.targetChain,
            lock.user,
            lock.amount,
            lock.timestamp,
            lock.txHash,
            lock.claimed
        );
    }
}

    

  



    
