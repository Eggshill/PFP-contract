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
    uint256 public amountForDevs;
    uint256 public amountForAuctionAndDev;
    bytes32 public override merkleRoot;
    bytes32 public keyHash;
    bool public revealed;
    uint256 public randomResult;
    uint256 public startingIndex;
    bool public isUriFrozen;
    uint256 public fee;

    // uint256 public auctionStartPrice;
    // uint256 public auctionEndPrice;
    // uint256 public auctionPriceCurveLength;
    // uint256 public auctionDropInterval;
    // uint256 public auctionDropPerStep =

    // // metadata URI
    string private _baseTokenURI;
    string private _notRevealedURI;

    struct SaleConfig {
        uint32 auctionSaleStartTime;
        uint32 publicSaleStartTime;
        uint64 mintlistPrice;
        uint64 publicPrice;
        uint32 publicSaleKey;
    }

    struct AuctionConfig {
        uint128 auctionStartPrice;
        uint128 auctionEndPrice;
        uint64 auctionPriceCurveLength;
        uint64 auctionDropInterval;
        uint128 auctionDropPerStep;
    }

    SaleConfig public saleConfig;
    AuctionConfig public auctionConfig;

    // mapping(address => uint256) public allowlist;

    function initialize(
        string memory name_,
        string memory symbol_,
        string memory notRevealedURI_,
        uint256 maxBatchSize_,
        uint256 collectionSize_,
        uint256 amountForAuctionAndDev_,
        uint256 amountForDevs_,
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
        amountForAuctionAndDev = amountForAuctionAndDev_;
        amountForDevs = amountForDevs_;
        require(amountForAuctionAndDev_ <= collectionSize_, "larger collection size needed");

        keyHash = keyHash_;
        fee = fee_;
    }

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "The caller is another contract");
        _;
    }

    // function allowlistMint() external payable callerIsUser {
    //     uint256 price = uint256(saleConfig.mintlistPrice);
    //     require(price != 0, "allowlist sale has not begun yet");
    //     require(allowlist[msg.sender] > 0, "not eligible for allowlist mint");
    //     require(totalSupply() + 1 <= collectionSize, "reached max supply");
    //     allowlist[msg.sender]--;
    //     _safeMint(msg.sender, 1);
    //     refundIfOver(price);
    // }

    function preSalesMint(
        uint256 index,
        uint256 thisTimeMint,
        uint256 maxMint,
        bytes32[] calldata merkleProof
    ) external payable override callerIsUser {
        uint256 price = uint256(saleConfig.mintlistPrice);
        require(price != 0, "allowlist sale has not begun yet");
        // require(allowlist[msg.sender] > 0, "not eligible for allowlist mint");
        require(numberMinted(msg.sender) + thisTimeMint <= maxMint, "can not mint this many");
        require(totalSupply() + thisTimeMint <= collectionSize, "reached max supply");

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, msg.sender, maxMint));
        // bytes32 node = keccak256(abi.encodePacked(index, account));
        require(MerkleProofUpgradeable.verify(merkleProof, merkleRoot, node), "MerkleDistributor: Invalid proof.");

        // Mark it claimed and send the token.
        // _setClaimed(index);
        // allowlist[msg.sender]--;
        _safeMint(msg.sender, thisTimeMint);
        refundIfOver(price);

        emit PreSalesMint(index, msg.sender, thisTimeMint, maxMint);
    }

    function publicSaleMint(uint256 quantity, uint256 callerPublicSaleKey) external payable callerIsUser {
        SaleConfig memory config = saleConfig;
        uint256 publicSaleKey = uint256(config.publicSaleKey);
        uint256 publicPrice = uint256(config.publicPrice);
        uint256 publicSaleStartTime = uint256(config.publicSaleStartTime);
        require(publicSaleKey == callerPublicSaleKey, "called with incorrect public sale key");

        require(isPublicSaleOn(publicPrice, publicSaleKey, publicSaleStartTime), "public sale has not begun yet");
        require(totalSupply() + quantity <= collectionSize, "reached max supply");
        require(numberMinted(msg.sender) + quantity <= maxPerAddressDuringMint, "can not mint this many");
        _safeMint(msg.sender, quantity);
        refundIfOver(publicPrice * quantity);
    }

    function auctionMint(uint256 quantity) external payable callerIsUser {
        uint256 _saleStartTime = uint256(saleConfig.auctionSaleStartTime);
        require(_saleStartTime != 0 && block.timestamp >= _saleStartTime, "sale has not started yet");
        require(totalSupply() + quantity <= amountForAuctionAndDev, "reached max supply");
        require(numberMinted(msg.sender) + quantity <= maxPerAddressDuringMint, "can not mint this many");
        uint256 totalCost = getAuctionPrice(_saleStartTime) * quantity;
        _safeMint(msg.sender, quantity);
        refundIfOver(totalCost);
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

    function updateMerkleRoot(bytes32 newMerkleRoot) external onlyOwner {
        merkleRoot = newMerkleRoot;
    }

    function endAuctionAndSetupNonAuctionSaleInfo(
        uint64 mintlistPriceWei,
        uint64 publicPriceWei,
        uint32 publicSaleStartTime
    ) external onlyOwner {
        saleConfig = SaleConfig(0, publicSaleStartTime, mintlistPriceWei, publicPriceWei, saleConfig.publicSaleKey);
    }

    // function setAuctionSaleStartTime(uint32 timestamp) external onlyOwner {
    //     saleConfig.auctionSaleStartTime = timestamp;
    // }

    function setAuctionConfig(
        uint32 timestamp,
        uint128 auctionStartPrice,
        uint128 auctionEndPrice,
        uint64 auctionPriceCurveLength,
        uint64 auctionDropInterval
    ) external onlyOwner {
        saleConfig.auctionSaleStartTime = timestamp;
        uint128 auctionDropPerStep = (auctionStartPrice - auctionEndPrice) /
            (auctionPriceCurveLength / auctionDropInterval);
        auctionConfig = AuctionConfig(
            auctionStartPrice,
            auctionEndPrice,
            auctionPriceCurveLength,
            auctionDropInterval,
            auctionDropPerStep
        );
    }

    function setPublicSaleKey(uint32 key) external onlyOwner {
        saleConfig.publicSaleKey = key;
    }

    // function seedAllowlist(address[] memory addresses, uint256[] memory numSlots) external onlyOwner {
    //     require(addresses.length == numSlots.length, "addresses does not match numSlots length");
    //     for (uint256 i = 0; i < addresses.length; i++) {
    //         allowlist[addresses[i]] = numSlots[i];
    //     }
    // }

    // For marketing etc.
    function devMint(uint256 quantity, address devAddress) external onlyOwner {
        require(totalSupply() + quantity <= amountForDevs, "too many already minted before dev mint");
        require(quantity % maxBatchSize == 0, "can only mint a multiple of the maxBatchSize");
        uint256 numChunks = quantity / maxBatchSize;
        for (uint256 i = 0; i < numChunks; i++) {
            _safeMint(devAddress, maxBatchSize);
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
                : "default token uri?";
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
