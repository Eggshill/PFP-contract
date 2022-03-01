// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC721AUpgradeable.sol";
import "./interfaces/IMerkleDistributor.sol";
import "./utils/VRFConsumerBaseV2Upgradeable.sol";
import "./utils/ProxyRegistry.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

contract NFT is
    VRFConsumerBaseV2Upgradeable,
    OwnableUpgradeable,
    ERC721AUpgradeable,
    ReentrancyGuardUpgradeable,
    IMerkleDistributor
{
    using StringsUpgradeable for uint256;
    using ECDSAUpgradeable for bytes32;

    VRFCoordinatorV2Interface COORDINATOR;
    LinkTokenInterface LINKTOKEN;

    uint256 public MAX_SUPPLY;

    uint256 public s_randomWord;
    uint256 public s_requestId;

    uint256 public maxPerAddressDuringMint;
    uint256 public amountForDevsAndPlatform;
    uint256 public amountForAuction;
    uint256 public startingIndex;
    bool public revealed;

    // metadata URI
    string private _baseTokenURI;
    string private _notRevealedURI;
    address private _proxyRegistryAddress;

    address public signer;
    bytes32 public override balanceTreeRoot;

    address public platform;
    uint256 public platformRate;

    uint256 publicSaleStartTime;

    struct ChainLinkConfig {
        bytes32 keyhash;
        uint64 s_subscriptionId;
        uint32 callbackGasLimit;
        uint16 requestConfirmations;
        uint32 numWords;
    }

    struct AuctionConfig {
        uint128 auctionStartPrice;
        uint128 auctionEndPrice;
        uint64 auctionPriceCurveLength;
        uint64 auctionDropInterval;
        uint128 auctionDropPerStep;
        uint32 auctionSaleStartTime;
    }

    struct PriceConfig {
        uint128 a;
        uint128 b;
    }

    ChainLinkConfig public chainLinkConfig;
    AuctionConfig public auctionConfig;
    PriceConfig public priceConfig;

    // mapping(address => uint256) public allowlist;

    event PreSalesMint(uint256 indexed index, address indexed account, uint256 amount, uint256 maxMint);
    event PublicSaleMint(address indexed user, uint256 number, uint256 totalCost);
    event AuctionMint(address indexed user, uint256 number, uint256 totalCost);

    function initialize(
        string memory name_,
        string memory symbol_,
        string memory notRevealedURI_,
        uint256 maxPerAddressDuringMint_,
        uint256 collectionSize_,
        uint256 amountForDevsAndPlatform_,
        bytes32 keyHash_,
        uint64 subscriptionId_,
        uint256 platformRate_,
        // [0: platformAddress, 1: signer, 2: vrfCoordinatorAddress, 3: linkAddress, 4: proxyRegistryAddress]
        address[5] calldata relatedAddresses_
    ) public initializer {
        __Ownable_init_unchained();
        __Context_init_unchained();
        __ERC165_init_unchained();
        __VRFConsumerBaseV2_init(relatedAddresses_[2]);
        __ERC721A_init_unchained(name_, symbol_, notRevealedURI_);

        require(amountForDevsAndPlatform_ <= collectionSize_, "larger collection size needed");

        maxPerAddressDuringMint = maxPerAddressDuringMint_;
        amountForDevsAndPlatform = amountForDevsAndPlatform_;
        amountForAuction = collectionSize_ - amountForDevsAndPlatform_;

        MAX_SUPPLY = collectionSize_;

        LINKTOKEN = LinkTokenInterface(relatedAddresses_[3]);
        COORDINATOR = VRFCoordinatorV2Interface(relatedAddresses_[2]);

        chainLinkConfig = ChainLinkConfig(
            keyHash_,
            subscriptionId_,
            100000, //callbackGasLimit
            3, //requestConfirmations
            1 //numWords
        );

        platform = relatedAddresses_[0];
        platformRate = platformRate_;
        signer = relatedAddresses_[1];
        _proxyRegistryAddress = relatedAddresses_[4];
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
        uint256 totalPrice = getNonAuctionPrice(thisTimeMint);
        require(totalPrice != 0, "allowlist sale has not begun yet");
        // require(allowlist[msg.sender] > 0, "not eligible for allowlist mint");
        require(numberMinted(msg.sender) + thisTimeMint <= maxMint, "can not mint this many");
        require(totalSupply() + thisTimeMint <= MAX_SUPPLY, "reached max supply");

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, msg.sender, maxMint));
        // bytes32 node = keccak256(abi.encodePacked(index, account));
        require(MerkleProofUpgradeable.verify(merkleProof, balanceTreeRoot, node), "MerkleDistributor: Invalid proof.");

        _safeMint(msg.sender, thisTimeMint);
        refundIfOver(totalPrice);

        emit PreSalesMint(index, msg.sender, thisTimeMint, maxMint);
    }

    function publicSaleMint(
        uint256 quantity,
        string calldata salt,
        bytes calldata signature
    ) external payable callerIsUser {
        require(verifySignature(salt, msg.sender, signature), "called with incorrect signature");

        uint256 totalPrice = getNonAuctionPrice(quantity);
        require(isPublicSaleOn(totalPrice), "public sale has not begun yet");
        require(totalSupply() + quantity <= MAX_SUPPLY, "reached max supply");
        require(numberMinted(msg.sender) + quantity <= maxPerAddressDuringMint, "can not mint this many");

        _safeMint(msg.sender, quantity);
        refundIfOver(totalPrice);

        emit PublicSaleMint(msg.sender, quantity, totalPrice);
    }

    function auctionMint(
        uint256 quantity,
        string calldata salt,
        bytes calldata signature
    ) external payable callerIsUser {
        require(verifySignature(salt, msg.sender, signature), "called with incorrect signature");

        uint256 _saleStartTime = uint256(auctionConfig.auctionSaleStartTime);
        require(_saleStartTime != 0 && block.timestamp >= _saleStartTime, "sale has not started yet");
        require(totalSupply() + quantity <= amountForAuction, "reached max supply");
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

    function isPublicSaleOn(uint256 publicPriceWei) public view returns (bool) {
        return publicPriceWei != 0 && block.timestamp >= publicSaleStartTime;
    }

    function getAuctionPrice(uint256 saleStartTime_) public view returns (uint256) {
        AuctionConfig memory config = auctionConfig;
        if (block.timestamp < saleStartTime_) {
            return config.auctionStartPrice;
        }
        if (block.timestamp - saleStartTime_ >= config.auctionPriceCurveLength) {
            return config.auctionEndPrice;
        } else {
            uint256 steps = (block.timestamp - saleStartTime_) / config.auctionDropInterval;
            return config.auctionStartPrice - (steps * config.auctionDropPerStep);
        }
    }

    function getNonAuctionPrice(uint256 quantity) public view returns (uint256) {
        PriceConfig memory config = priceConfig;
        return config.a * quantity + config.b;
    }

    function setMaxPerAddressDuringMint(uint32 quantity) external onlyOwner {
        maxPerAddressDuringMint = quantity;
    }

    function updatePresaleInfo(
        bytes32 newBalanceTreeRoot_,
        uint128 a_,
        uint128 b_
    ) external onlyOwner {
        balanceTreeRoot = newBalanceTreeRoot_;
        priceConfig = PriceConfig(a_, b_);
    }

    function endAuctionAndSetupPublicSaleInfo(
        uint32 publicSaleStartTime_,
        uint128 a_,
        uint128 b_
    ) external onlyOwner {
        delete auctionConfig;
        delete priceConfig;

        publicSaleStartTime = publicSaleStartTime_;
        priceConfig = PriceConfig(a_, b_);
    }

    // function setAuctionSaleStartTime(uint32 timestamp) external onlyOwner {
    //     publicSaleConfig.auctionSaleStartTime = timestamp;
    // }

    function endPublicSalesAndSetupAuctionSaleInfo(
        uint32 auctionSaleStartTime_,
        uint128 auctionStartPrice_,
        uint128 auctionEndPrice_,
        uint64 auctionPriceCurveLength_,
        uint64 auctionDropInterval_,
        uint256 amountForAuction_
    ) external onlyOwner {
        delete publicSaleStartTime;

        require(amountForAuction_ < MAX_SUPPLY - totalSupply(), "too much for aucction");
        amountForAuction = amountForAuction_;
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

    function setSigner(address signer_) external onlyOwner {
        signer = signer_;
    }

    // function seedAllowlist(address[] memory addresses, uint256[] memory numSlots) external onlyOwner {
    //     require(addresses.length == numSlots.length, "addresses does not match numSlots length");
    //     for (uint256 i = 0; i < addresses.length; i++) {
    //         allowlist[addresses[i]] = numSlots[i];
    //     }
    // }

    // For marketing etc.
    function devMint(uint256 totalQuantity, address devAddress) external onlyOwner {
        require(totalSupply() + totalQuantity <= amountForDevsAndPlatform, "too many already minted before dev mint");

        uint256 quantityForPlatform = totalQuantity * platformRate;

        _safeMint(platform, quantityForPlatform);
        _safeMint(devAddress, totalQuantity - quantityForPlatform);
    }

    function setBaseURI(string calldata baseURI) public onlyOwner {
        _baseTokenURI = baseURI;
    }

    function setNotRevealedURI(string calldata notRevealedURI) external onlyOwner {
        _notRevealedURI = notRevealedURI;
    }

    function reveal(string calldata baseURI) external onlyOwner {
        require(!revealed, "Already revealed");
        require(startingIndex == 0, "Already set Starting index");

        ChainLinkConfig memory config = chainLinkConfig;

        s_requestId = COORDINATOR.requestRandomWords(
            config.keyhash,
            config.s_subscriptionId,
            config.requestConfirmations,
            config.callbackGasLimit,
            config.numWords
        );

        setBaseURI(baseURI);

        // revealed = true;
    }

    function updateChainLinkConfig(
        bytes32 keyhash_,
        uint16 requestConfirmations_,
        uint32 callbackGasLimit_
    ) external onlyOwner {
        ChainLinkConfig memory config = chainLinkConfig;

        s_requestId = COORDINATOR.requestRandomWords(
            keyhash_,
            config.s_subscriptionId,
            requestConfirmations_,
            callbackGasLimit_,
            config.numWords
        );
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
                ? string(abi.encodePacked(baseURI, ((tokenId + startingIndex) % MAX_SUPPLY).toString(), ".json"))
                : "baseuri not set correctly";
    }

    function isApprovedForAll(address _owner, address operator) public view override returns (bool) {
        // Whitelist OpenSea Proxy.
        ProxyRegistry proxyRegistry = ProxyRegistry(_proxyRegistryAddress);
        if (address(proxyRegistry.proxies(_owner)) == operator) {
            return true;
        }

        return super.isApprovedForAll(_owner, operator);
    }

    function withdrawMoney() external nonReentrant {
        uint256 balance = address(this).balance;
        bool success;

        if (platform != address(0)) {
            (success, ) = platform.call{value: (balance * (platformRate)) / 100}("");
            require(success, "Failed to send Ether");
        }

        balance = address(this).balance;

        (success, ) = owner().call{value: balance}("");
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

    function verifySignature(
        string calldata _salt,
        address _userAddress,
        bytes memory signature
    ) public view returns (bool) {
        bytes32 rawMessageHash = _getMessageHash(_salt, _userAddress);

        return _recover(rawMessageHash, signature) == signer;
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function _getMessageHash(string calldata _salt, address _userAddress) internal view returns (bytes32) {
        return keccak256(abi.encode(_salt, address(this), _userAddress));
    }

    function _recover(bytes32 _rawMessageHash, bytes memory signature) internal pure returns (address) {
        return _rawMessageHash.toEthSignedMessageHash().recover(signature);
    }

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomWords(
        uint256, /* requestId */
        uint256[] memory randomWords
    ) internal virtual override {
        s_randomWord = randomWords[0];

        startingIndex = (s_randomWord % MAX_SUPPLY);

        // Prevent default sequence
        if (startingIndex == 0) {
            unchecked {
                startingIndex = startingIndex + 1;
            }
        }

        revealed = true;
    }
}
