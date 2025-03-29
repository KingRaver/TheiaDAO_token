// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title ScientistNFT
 * @dev Soulbound NFT contract for ecological oversight with multi-sig capabilities
 */
contract ScientistNFT is ERC721, AccessControl {
    using Counters for Counters.Counter;
    using ECDSA for bytes32;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SCIENTIST_ROLE = keccak256("SCIENTIST_ROLE");
    
    Counters.Counter private _tokenIdCounter;
    
    // Scientist details
    struct ScientistInfo {
        string name;
        string specialization;
        string credentials;
        bool isActive;
        uint256 appointmentDate;
    }
    
    mapping(uint256 => ScientistInfo) public scientists;

    // Multi-signature mechanism
    struct MultiSigAction {
        bytes32 actionHash;
        uint256 proposedTime;
        uint256 requiredSignatures;
        uint256 signatureCount;
        mapping(address => bool) hasSigned;
        bool executed;
    }
    
    mapping(bytes32 => MultiSigAction) public pendingActions;
    bytes32[] public pendingActionHashes;

    uint256 public requiredSignatures = 1; // Start with single signature, can be upgraded
    
    // Events
    event ScientistNFTIssued(uint256 indexed tokenId, address indexed scientist, string name);
    event ScientistInfoUpdated(uint256 indexed tokenId, string name, string specialization);
    event ActionProposed(bytes32 indexed actionHash, address proposer, string actionType);
    event ActionSigned(bytes32 indexed actionHash, address signer);
    event ActionExecuted(bytes32 indexed actionHash);
    event RequiredSignaturesChanged(uint256 oldValue, uint256 newValue);
    
    /**
     * @dev Constructor
     */

     /**
     * @dev Issues a new Scientist NFT (soulbound token)
     * @param to Address to issue the NFT to
     * @param name Scientist's name
     * @param specialization Scientist's field of expertise
     * @param credentials Scientist's credentials and qualifications
     * @return tokenId The ID of the newly minted NFT
     */
     function issueScientistNFT(
        address to,
        string memory name,
        string memory specialization,
        string memory credentials
    ) external onlyRole(ADMIN_ROLE) returns (uint256) {
        require(balanceOf(to) == 0, "Address already has a scientist NFT");
        
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        
        _safeMint(to, tokenId);
        
        scientists[tokenId] = ScientistInfo({
            name: name,
            specialization: specialization,
            credentials: credentials,
            isActive: true,
            appointmentDate: block.timestamp
        });
        
        _grantRole(SCIENTIST_ROLE, to);
        
        emit ScientistNFTIssued(tokenId, to, name);
        
        return tokenId;
    }

    /**
     * @dev Updates scientist information
     * @param tokenId ID of the scientist NFT
     * @param name Updated name
     * @param specialization Updated specialization
     * @param credentials Updated credentials
     */
    function updateScientistInfo(
        uint256 tokenId,
        string memory name,
        string memory specialization,
        string memory credentials
    ) external {
        require(_isApprovedOrOwner(msg.sender, tokenId) || hasRole(ADMIN_ROLE, msg.sender), 
                "Not authorized");
        
        ScientistInfo storage info = scientists[tokenId];
        
        info.name = name;
        info.specialization = specialization;
        info.credentials = credentials;
        
        emit ScientistInfoUpdated(tokenId, name, specialization);
    }
    
    /**
     * @dev Proposes a multi-signature action
     * @param actionType Type of action being proposed
     * @param actionData Encoded data for the action
     * @return actionHash Hash identifying the action
     */
    function proposeAction(
        string calldata actionType,
        bytes calldata actionData
    ) external onlyRole(SCIENTIST_ROLE) returns (bytes32) {
        bytes32 actionHash = keccak256(abi.encodePacked(actionType, actionData, block.timestamp));
        
        MultiSigAction storage action = pendingActions[actionHash];
        action.actionHash = actionHash;
        action.proposedTime = block.timestamp;
        action.requiredSignatures = requiredSignatures;
        action.signatureCount = 1; // Proposer counts as first signature
        action.hasSigned[msg.sender] = true;
        
        pendingActionHashes.push(actionHash);
        
        emit ActionProposed(actionHash, msg.sender, actionType);
        
        return actionHash;
    }
    
    /**
     * @dev Signs a pending multi-signature action
     * @param actionHash Hash of the action to sign
     */
    function signAction(bytes32 actionHash) external onlyRole(SCIENTIST_ROLE) {
        MultiSigAction storage action = pendingActions[actionHash];
        
        require(action.proposedTime > 0, "Action does not exist");
        require(!action.executed, "Action already executed");
        require(!action.hasSigned[msg.sender], "Already signed");
        
        action.hasSigned[msg.sender] = true;
        action.signatureCount++;
        
        emit ActionSigned(actionHash, msg.sender);
        
        // Auto-execute if we have enough signatures
        if (action.signatureCount >= action.requiredSignatures) {
            action.executed = true;
            emit ActionExecuted(actionHash);
            
            // In a full implementation, this would trigger the actual action execution
            // which would be handled by a separate function based on the action type
        }
    }
    
    /**
     * @dev Updates the required number of signatures for multi-sig actions
     * @param newRequiredSignatures New number of required signatures
     */
    function updateRequiredSignatures(uint256 newRequiredSignatures) external onlyRole(ADMIN_ROLE) {
        require(newRequiredSignatures > 0, "Must require at least one signature");
        
        emit RequiredSignaturesChanged(requiredSignatures, newRequiredSignatures);
        requiredSignatures = newRequiredSignatures;
    }
    
    /**
     * @dev Make the NFT soulbound by preventing transfers
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        
        // Allow minting (new issuance) but prevent transfers
        if (from != address(0)) {
            require(hasRole(ADMIN_ROLE, msg.sender), "Token is soulbound");
        }
    }
    
    /**
     * @dev Returns whether a scientist is active
     * @param tokenId ID of the scientist NFT
     * @return active Whether the scientist is active
     */
    function isScientistActive(uint256 tokenId) external view returns (bool) {
        return scientists[tokenId].isActive;
    }
    
    /**
     * @dev Get all pending action hashes
     * @return Array of pending action hashes
     */
    function getPendingActionHashes() external view returns (bytes32[] memory) {
        return pendingActionHashes;
    }
    
    // The following function is used to comply with ERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
