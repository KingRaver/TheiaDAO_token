// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title THEIAToken
 * @dev Governance token for TheiaDAO with locking, revenue sharing, and cross-chain capabilities
 */
contract THEIAToken is ERC20Votes, AccessControl, ReentrancyGuard {
    // Roles
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    // Scientist NFT interface
    IERC721 public scientistNFT;
    uint256 public scientistTokenId;
    
    // Revenue distribution
    uint256 public revenuePercentage = 100; // 1% represented as 100 basis points
    mapping(address => uint256) public pendingRewards;
    uint256 public totalRewards;
    
    // Locking mechanism
    struct Lock {
        uint256 amount;
        uint256 unlockTime;
        bool permanent; // If true, can only be unlocked via governance
    }
    mapping(address => Lock) public locks;
    uint256 public totalLocked;
    
    // Governance parameters
    uint256 public proposalThreshold; // Min tokens needed to submit proposal
    uint256 public quadraticVoteDivisor; // Parameter for quadratic voting calculation
    mapping(uint256 => bool) public proposalVetoed; // Tracking vetoed proposals
    
    // Impact metrics
    struct ImpactMetric {
        string name;
        uint256 value;
        uint256 lastUpdated;
    }
    mapping(bytes32 => ImpactMetric) public impactMetrics;
    bytes32[] public impactMetricKeys;
    
    // Events
    event TokensLocked(address indexed user, uint256 amount, uint256 unlockTime, bool permanent);
    event TokensUnlocked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RevenuePercentageUpdated(uint256 oldPercentage, uint256 newPercentage);
    event ProposalVetoed(uint256 indexed proposalId, address vetoer);
    event ImpactMetricUpdated(bytes32 key, string name, uint256 value);
    
    /**
     * @dev Constructor
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param scientistNFTAddress Address of the Scientist NFT contract
     * @param initialScientistTokenId Token ID of the initial Scientist NFT
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address scientistNFTAddress,
        uint256 initialScientistTokenId
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        
        scientistNFT = IERC721(scientistNFTAddress);
        scientistTokenId = initialScientistTokenId;
        
        proposalThreshold = 1000 * 10**18; // 1000 tokens
        quadraticVoteDivisor = 10; // Configurable parameter for quadratic voting
    }
    
    /**
     * @dev Locks tokens for governance participation and revenue sharing
     * @param amount Amount to lock
     * @param unlockTime Time when tokens can be unlocked (0 for permanent lock)
     * @param permanent Whether the lock is permanent (can only be unlocked via governance)
     */
    function lockTokens(uint256 amount, uint256 unlockTime, bool permanent) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        // Transfer tokens to the contract
        _transfer(msg.sender, address(this), amount);
        
        // Update lock
        locks[msg.sender].amount += amount;
        if (permanent) {
            locks[msg.sender].permanent = true;
        } else if (unlockTime > locks[msg.sender].unlockTime) {
            locks[msg.sender].unlockTime = unlockTime;
        }
        
        totalLocked += amount;
        
        emit TokensLocked(msg.sender, amount, unlockTime, permanent);
    }
    
    /**
     * @dev Unlocks tokens if conditions are met
     * @param amount Amount to unlock
     */
    function unlockTokens(uint256 amount) external nonReentrant {
        Lock storage userLock = locks[msg.sender];
        require(amount > 0 && amount <= userLock.amount, "Invalid amount");
        require(!userLock.permanent, "Tokens are permanently locked");
        require(block.timestamp >= userLock.unlockTime, "Tokens are still locked");
        
        // Update lock
        userLock.amount -= amount;
        totalLocked -= amount;
        
        // Transfer tokens back to user
        _transfer(address(this), msg.sender, amount);
        
        emit TokensUnlocked(msg.sender, amount);
    }
    
    /**
     * @dev Governance unlock for permanently locked tokens
     * @param user Address of token holder
     * @param amount Amount to unlock
     */
    function governanceUnlock(address user, uint256 amount) external {
        // Implement governance check here
        // This would typically check if this is part of an executed proposal
        
        // Check scientist NFT veto hasn't been applied
        // Implementation for this would be in the governance contract
        
        Lock storage userLock = locks[user];
        require(amount > 0 && amount <= userLock.amount, "Invalid amount");
        
        // Update lock
        userLock.amount -= amount;
        totalLocked -= amount;
        
        // Transfer tokens back to user
        _transfer(address(this), user, amount);
        
        emit TokensUnlocked(user, amount);
    }
    
    /**
     * @dev Distributes revenue to locked token holders
     */
    function distributeRevenue() external payable {
        require(totalLocked > 0, "No tokens locked");
        
        totalRewards += msg.value;
        // Revenue distribution happens when users claim rewards
    }
    
    /**
     * @dev Claims pending rewards for a user
     */
    function claimRewards() external nonReentrant {
        Lock storage userLock = locks[msg.sender];
        require(userLock.amount > 0, "No locked tokens");
        
        // Calculate share of rewards
        uint256 share = (userLock.amount * totalRewards) / totalLocked;
        require(share > 0, "No rewards to claim");
        
        // Reset rewards
        totalRewards -= share;
        
        // Transfer rewards
        (bool success, ) = payable(msg.sender).call{value: share}("");
        require(success, "Transfer failed");
        
        emit RewardsClaimed(msg.sender, share);
    }
    
    /**
     * @dev Updates the revenue percentage (requires governance and scientist approval)
     * @param newPercentage New percentage in basis points (100 = 1%)
     */
    function updateRevenuePercentage(uint256 newPercentage) external onlyRole(ADMIN_ROLE) {
        // In real implementation, this would check for governance approval
        // and scientist NFT holder approval
        
        emit RevenuePercentageUpdated(revenuePercentage, newPercentage);
        revenuePercentage = newPercentage;
    }
    
    /**
     * @dev Veto a proposal (can only be called by the scientist NFT holder)
     * @param proposalId ID of the proposal to veto
     */
    function vetoProposal(uint256 proposalId) external {
        require(
            scientistNFT.ownerOf(scientistTokenId) == msg.sender,
            "Caller is not the scientist NFT owner"
        );
        
        proposalVetoed[proposalId] = true;
        emit ProposalVetoed(proposalId, msg.sender);
    }
    
    /**
     * @dev Updates impact metrics (could be called by authorized oracles)
     * @param key Identifier for the metric
     * @param name Human readable name for the metric
     * @param value Current value of the metric
     */
    function updateImpactMetric(bytes32 key, string calldata name, uint256 value) 
        external onlyRole(ADMIN_ROLE) 
    {
        // In production, this might have more complex access control
        // or verification of data from trusted oracles
        
        if (impactMetrics[key].lastUpdated == 0) {
            impactMetricKeys.push(key);
        }
        
        impactMetrics[key] = ImpactMetric({
            name: name,
            value: value,
            lastUpdated: block.timestamp
        });
        
        emit ImpactMetricUpdated(key, name, value);
    }
    
    /**
     * @dev Calculate voting power with quadratic voting formula
     * @param account Address to check voting power for
     * @return Voting power with quadratic scaling
     */
    function getVotingPower(address account) public view returns (uint256) {
        uint256 lockedAmount = locks[account].amount;
        if (lockedAmount == 0) return 0;
        
        // Simple quadratic calculation - square root of tokens
        // In a real implementation, this would be more sophisticated
        return sqrt(lockedAmount) * quadraticVoteDivisor;
    }
    
    /**
     * @dev Helper function to calculate square root
     * @param x Value to find square root of
     * @return y Square root of x
     */
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
    
    // Bridge and cross-chain functionality would be implemented here
    // This would involve functions to lock tokens on one chain and mint on another
    
    // Additional functions for token management and governance
    // would be implemented here
    
    // Override necessary ERC20Votes functions to integrate with the locking mechanism
}
