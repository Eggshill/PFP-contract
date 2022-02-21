// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC721AUpgradeable.sol";
import "./interfaces/IMerkleDistributor.sol";
import "./utils/VRFConsumerBaseUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";

contract NFT is
    VRFConsumerBaseUpgradeable,
    OwnableUpgradeable,
    ERC721AUpgradeable,
    ReentrancyGuardUpgradeable,
    IMerkleDistributor
{
    using StringsUpgradeable for uint256;

    uint256 public maxPerAddressDuringMint;
    uint256 public amountForDevsAndPlatform;
    bytes32 public keyHash;
    bool public revealed;
    uint256 public randomResult;
    uint256 public startingIndex;
    bool public isUriFrozen;
    uint256 public fee;

    // metadata URI
    string private _baseTokenURI;
    string private _notRevealedURI;

    bytes32 public override balanceTreeRoot;
    uint256 public mintlistPrice; // in Wei

    struct PublicSaleConfig {
        uint32 publicSaleStartTime;
        uint64 publicPrice;
        uint32 publicSaleKey;
    }

    struct AuctionConfig {
        uint128 auctionStartPrice;
        uint128 auctionEndPrice;
        uint64 auctionPriceCurveLength;
        uint64 auctionDropInterval;
        uint128 auctionDropPerStep;
        uint32 auctionSaleStartTime;
    }

    PublicSaleConfig public publicSaleConfig;
    AuctionConfig public auctionConfig;

    // mapping(address => uint256) public allowlist;

    event PreSalesMint(uint256 indexed index, address indexed account, uint256 amount, uint256 maxMint);
    event PublicSaleMint(address indexed user, uint256 number);
    event AuctionMint(address indexed user, uint256 number, uint256 totalCost);

    function initialize(
        string memory name_,
        string memory symbol_,
        string memory notRevealedURI_,
        uint256 maxBatchSize_,
        uint256 collectionSize_,
        uint256 amountForDevsAndPlatform_,
        address vrfCoordinatorAddress_,
        address linkAddress_,
        bytes32 keyHash_,
        uint256 fee_
    ) public initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __VRFConsumerBase_init(vrfCoordinatorAddress_, linkAddress_);
        __ERC721A_init_unchained(name_, symbol_, notRevealedURI_, maxBatchSize_, collectionSize_);

        maxPerAddressDuringMint = maxBatchSize_;
        amountForDevsAndPlatform = amountForDevsAndPlatform_;

        keyHash = keyHash_;
        fee = fee_;
    }

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "The caller is another contract");
        _;
    }

    function preSalesMint(
        uint256 index,
        uint256 thisTimeMint,
        uint256 maxMint,
        bytes32[] calldata merkleProof
    ) external payable override callerIsUser {
        uint256 price = mintlistPrice;
        require(price != 0, "allowlist sale has not begun yet");
        // require(allowlist[msg.sender] > 0, "not eligible for allowlist mint");
        require(numberMinted(msg.sender) + thisTimeMint <= maxMint, "can not mint this many");
        require(totalSupply() + thisTimeMint <= collectionSize, "reached max supply");

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, msg.sender, maxMint));
        // bytes32 node = keccak256(abi.encodePacked(index, account));
        require(MerkleProofUpgradeable.verify(merkleProof, balanceTreeRoot, node), "MerkleDistributor: Invalid proof.");

        // Mark it claimed and send the token.
        // _setClaimed(index);
        // allowlist[msg.sender]--;
        _safeMint(msg.sender, thisTimeMint);
        refundIfOver(price * thisTimeMint);

        emit PreSalesMint(index, msg.sender, thisTimeMint, maxMint);
    }

    function publicSaleMint(uint256 quantity, uint256 callerPublicSaleKey) external payable callerIsUser {
        PublicSaleConfig memory config = publicSaleConfig;
        uint256 publicSaleKey = uint256(config.publicSaleKey);
        uint256 publicPrice = uint256(config.publicPrice);
        uint256 publicSaleStartTime = uint256(config.publicSaleStartTime);
        require(publicSaleKey == callerPublicSaleKey, "called with incorrect public sale key");

        require(isPublicSaleOn(publicPrice, publicSaleKey, publicSaleStartTime), "public sale has not begun yet");
        require(totalSupply() + quantity <= collectionSize, "reached max supply");
        require(numberMinted(msg.sender) + quantity <= maxPerAddressDuringMint, "can not mint this many");
        _safeMint(msg.sender, quantity);
        refundIfOver(publicPrice * quantity);

        emit PublicSaleMint(msg.sender, quantity);
    }

    function auctionMint(uint256 quantity) external payable callerIsUser {
        uint256 _saleStartTime = uint256(auctionConfig.auctionSaleStartTime);
        require(_saleStartTime != 0 && block.timestamp >= _saleStartTime, "sale has not started yet");
        require(totalSupply() + quantity <= maxBatchSize - amountForDevsAndPlatform, "reached max supply");
        require(numberMinted(msg.sender) + quantity <= maxPerAddressDuringMint, "can not mint this many");
        uint256 totalCost = getAuctionPrice(_saleStartTime) * quantity;
        _safeMint(msg.sender, quantity);
        refundIfOver(totalCost);

        emit AuctionMint(msg.sender, quantity, totalCost);
    }

    function refundIfOver(uint256 price) private {
        require(msg.value >= price, "Need to send more ETH.");
        if (msg.value > price) {
            (bool success, ) = payable(msg.sender).call{value: msg.value - price}("");
            require(success, "Failed to send Ether");
        }
    }

    function isPublicSaleOn(
        uint256 publicPriceWei,
        uint256 publicSaleKey,
        uint256 publicSaleStartTime
    ) public view returns (bool) {
        return publicPriceWei != 0 && publicSaleKey != 0 && block.timestamp >= publicSaleStartTime;
    }

    function getAuctionPrice(uint256 _saleStartTime) public view returns (uint256) {
        AuctionConfig memory config = auctionConfig;
        if (block.timestamp < _saleStartTime) {
            return config.auctionStartPrice;
        }
        if (block.timestamp - _saleStartTime >= config.auctionPriceCurveLength) {
            return config.auctionEndPrice;
        } else {
            uint256 steps = (block.timestamp - _saleStartTime) / config.auctionDropInterval;
            return config.auctionStartPrice - (steps * config.auctionDropPerStep);
        }
    }

    function setMaxPerAddressDuringMint(uint32 quantity) external onlyOwner {
        require(quantity < maxBatchSize, "Exceed max mint batch number");
        maxPerAddressDuringMint = quantity;
    }

    function updatePresaleInfo(bytes32 newBalanceTreeRoot, uint256 mintlistPriceWei) external onlyOwner {
        balanceTreeRoot = newBalanceTreeRoot;
        mintlistPrice = mintlistPriceWei;
    }

    function endAuctionAndSetupPublicSaleInfo(uint64 publicPriceWei, uint32 publicSaleStartTime) external onlyOwner {
        delete auctionConfig;

        publicSaleConfig = PublicSaleConfig(publicSaleStartTime, publicPriceWei, publicSaleConfig.publicSaleKey);
    }

    // function setAuctionSaleStartTime(uint32 timestamp) external onlyOwner {
    //     publicSaleConfig.auctionSaleStartTime = timestamp;
    // }

    function endPublicSalesAndSetupAuctionSaleInfo(
        uint32 auctionSaleStartTime_,
        uint128 auctionStartPrice_,
        uint128 auctionEndPrice_,
        uint64 auctionPriceCurveLength_,
        uint64 auctionDropInterval_
    ) external onlyOwner {
        delete publicSaleConfig;

        uint128 auctionDropPerStep = (auctionStartPrice_ - auctionEndPrice_) /
            (auctionPriceCurveLength_ / auctionDropInterval_);
        auctionConfig = AuctionConfig(
            auctionStartPrice_,
            auctionEndPrice_,
            auctionPriceCurveLength_,
            auctionDropInterval_,
            auctionDropPerStep,
            auctionSaleStartTime_
        );
    }

    function setPublicSaleKey(uint32 key) external onlyOwner {
        publicSaleConfig.publicSaleKey = key;
    }

    // function seedAllowlist(address[] memory addresses, uint256[] memory numSlots) external onlyOwner {
    //     require(addresses.length == numSlots.length, "addresses does not match numSlots length");
    //     for (uint256 i = 0; i < addresses.length; i++) {
    //         allowlist[addresses[i]] = numSlots[i];
    //     }
    // }

    // For marketing etc.
    function devMint(
        uint256 totalQuantity,
        uint256 quantityForPlatform,
        address devAddress,
        address platformAddress
    ) external onlyOwner {
        require(totalSupply() + totalQuantity <= amountForDevsAndPlatform, "too many already minted before dev mint");
        require(quantityForPlatform < totalQuantity, "too much for platform");

        chunksMint(quantityForPlatform, platformAddress);
        chunksMint(totalQuantity - quantityForPlatform, devAddress);
    }

    function chunksMint(uint256 quantity, address to) internal {
        uint256 _maxBatchSize = maxBatchSize;
        uint256 numChunks = quantity / _maxBatchSize;
        uint256 remainder = quantity % _maxBatchSize;

        for (uint256 i = 0; i < numChunks; i++) {
            _safeMint(to, _maxBatchSize);
        }
        if (remainder > 0) {
            _safeMint(to, remainder);
        }
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string calldata baseURI) external onlyOwner {
        require(!isUriFrozen, "Token URI is frozen");
        _baseTokenURI = baseURI;
    }

    function setNotRevealedURI(string calldata notRevealedURI) external onlyOwner {
        _notRevealedURI = notRevealedURI;
    }

    function freezeTokenURI() external onlyOwner {
        require(!isUriFrozen, "Token URI is frozen");
        isUriFrozen = true;
    }

    function reveal() external onlyOwner {
        require(!revealed, "Already revealed");
        require(startingIndex == 0, "Already set Starting index");

        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK");
        requestRandomness(keyHash, fee);

        // revealed = true;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        if (revealed == false) {
            return _notRevealedURI;
        }

        require(startingIndex != 0, "randomness request hasn't finalized");

        string memory baseURI = _baseURI();
        return
            bytes(baseURI).length != 0
                ? string(abi.encodePacked(baseURI, ((tokenId + startingIndex) % collectionSize).toString()))
                : "baseuri not set correctly";
    }

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal virtual override {
        startingIndex = (randomness % collectionSize);

        // Prevent default sequence
        if (startingIndex == 0) {
            unchecked {
                startingIndex = startingIndex + 1;
            }
        }

        revealed = true;
    }

    function withdrawMoney() external nonReentrant {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }

    function contractURI() public view override returns (string memory) {
        return _notRevealedURI;
    }

    function numberMinted(address owner) public view returns (uint256) {
        return _numberMinted(owner);
    }

    function getOwnershipData(uint256 tokenId) external view returns (TokenOwnership memory) {
        return ownershipOf(tokenId);
    }
}
