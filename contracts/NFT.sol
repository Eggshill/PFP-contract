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
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

error ExceedCollectionSize();
error CallerIsContract();
error MintTooMuch();
error ReachMaxDevMintReserve();
error InvalidProof();
error InvalidSignature();
error PreSaleNotBegin();
error PublicSaleNotBegin();
error AuctionNotBegin();
error ReachAuctionReserve();
error EtherNotEnough();
error TooMuchForAuction();
error ArrayLengthNotMatch();
error AlreadyRevealed();
error AlreadySetStartingIndex();
error NonexistentToken();
error RandomnessRequestNotFinalized();
error SendEtherFailed();
error TransferFailed();

contract NFT is
    VRFConsumerBaseV2Upgradeable,
    OwnableUpgradeable,
    ERC721AUpgradeable,
    ReentrancyGuardUpgradeable,
    IMerkleDistributor
{
    using StringsUpgradeable for uint256;
    using ECDSAUpgradeable for bytes32;

    ProxyRegistry public constant PROXY_REGISTRY = ProxyRegistry(0xF57B2c51dED3A29e6891aba85459d600256Cf317);
    VRFCoordinatorV2Interface public constant VRF_COORDINATOR =
        VRFCoordinatorV2Interface(0x6168499c0cFfCaCD319c818142124B7A15E857ab);
    bytes32 public constant KEY_HASH = 0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc;

    uint256 public MAX_SUPPLY;

    uint256 public s_randomWord;
    uint256 public s_requestId;

    uint256 public maxPerAddressDuringMint;
    uint256 public amountForDevsAndPlatform;
    uint256 public amountForAuction;
    uint256 public initialrandomIndex;
    bool public revealed;

    // metadata URI
    string private _baseTokenURI;
    string private _notRevealedURI;

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
        uint128 preSalePriceA;
        uint128 preSalePriceB;
        uint128 publicSalePriceA;
        uint128 publicSalePriceB;
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
        uint64 subscriptionId_,
        uint256 platformRate_,
        address platformAddress_,
        address signer_
    ) public initializer {
        __Ownable_init_unchained();
        __Context_init_unchained();
        __ERC165_init_unchained();
        __VRFConsumerBaseV2_init(address(VRF_COORDINATOR));
        __ERC721A_init_unchained(name_, symbol_, notRevealedURI_);

        if (amountForDevsAndPlatform_ >= collectionSize_) revert ExceedCollectionSize();

        maxPerAddressDuringMint = maxPerAddressDuringMint_;
        amountForDevsAndPlatform = amountForDevsAndPlatform_;
        amountForAuction = collectionSize_ - amountForDevsAndPlatform_;

        MAX_SUPPLY = collectionSize_;

        chainLinkConfig = ChainLinkConfig(
            KEY_HASH,
            subscriptionId_,
            100000, //callbackGasLimit
            3, //requestConfirmations
            1 //numWords
        );

        platform = platformAddress_;
        platformRate = platformRate_;
        signer = signer_;
    }

    modifier callerIsUser() {
        if (tx.origin != msg.sender) revert CallerIsContract();
        _;
    }

    function preSalesMint(
        uint256 index,
        uint256 thisTimeMint,
        uint256 maxMint,
        bytes32[] calldata merkleProof
    ) external payable override callerIsUser {
        uint256 totalPrice = getPreSalePrice(thisTimeMint);

        if (totalPrice == 0) revert PreSaleNotBegin();

        uint256 userTotalMinted = numberMinted(msg.sender) + thisTimeMint;

        if (userTotalMinted > maxPerAddressDuringMint && userTotalMinted > maxMint) revert MintTooMuch();
        if (totalSupply() + thisTimeMint > MAX_SUPPLY) revert ExceedCollectionSize();

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, msg.sender, maxMint));
        if (!MerkleProofUpgradeable.verify(merkleProof, balanceTreeRoot, node)) revert InvalidProof();

        refundIfOver(totalPrice);
        _safeMint(msg.sender, thisTimeMint);

        emit PreSalesMint(index, msg.sender, thisTimeMint, maxMint);
    }

    function publicSaleMint(
        uint256 quantity,
        string calldata salt,
        bytes calldata signature
    ) external payable callerIsUser {
        if (!verifySignature(salt, msg.sender, quantity, signature)) revert InvalidSignature();

        uint256 totalPrice = getPublicSalePrice(quantity);

        if (!isPublicSaleOn(totalPrice)) revert PublicSaleNotBegin();
        if (numberMinted(msg.sender) + quantity > maxPerAddressDuringMint) revert MintTooMuch();
        if (totalSupply() + quantity > MAX_SUPPLY) revert ExceedCollectionSize();

        refundIfOver(totalPrice);
        _safeMint(msg.sender, quantity);

        emit PublicSaleMint(msg.sender, quantity, totalPrice);
    }

    function auctionMint(
        uint256 quantity,
        string calldata salt,
        bytes calldata signature
    ) external payable callerIsUser {
        if (!verifySignature(salt, msg.sender, quantity, signature)) revert InvalidSignature();

        uint256 _saleStartTime = uint256(auctionConfig.auctionSaleStartTime);

        if (_saleStartTime == 0 || block.timestamp < _saleStartTime) revert AuctionNotBegin();

        if (totalSupply() + quantity > amountForAuction) revert ReachAuctionReserve();
        if (numberMinted(msg.sender) + quantity > maxPerAddressDuringMint) revert MintTooMuch();

        uint256 totalCost = getAuctionPrice(_saleStartTime) * quantity;

        refundIfOver(totalCost);
        _safeMint(msg.sender, quantity);

        emit AuctionMint(msg.sender, quantity, totalCost);
    }

    function refundIfOver(uint256 price) private {
        if (msg.value < price) revert EtherNotEnough();
        if (msg.value > price) {
            (bool success, ) = payable(msg.sender).call{value: msg.value - price}("");
            if (!success) revert SendEtherFailed();
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

    function getPreSalePrice(uint256 quantity) public view returns (uint256) {
        PriceConfig memory config = priceConfig;
        return config.preSalePriceA * quantity + config.preSalePriceB;
    }

    function getPublicSalePrice(uint256 quantity) public view returns (uint256) {
        PriceConfig memory config = priceConfig;
        return config.publicSalePriceA * quantity + config.publicSalePriceB;
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
        PriceConfig memory config = priceConfig;
        priceConfig = PriceConfig(a_, b_, config.publicSalePriceA, config.publicSalePriceB);
    }

    function endAuctionAndSetupPublicSaleInfo(
        uint32 publicSaleStartTime_,
        uint128 a_,
        uint128 b_
    ) external onlyOwner {
        delete auctionConfig;

        PriceConfig memory config = priceConfig;
        publicSaleStartTime = publicSaleStartTime_;
        priceConfig = PriceConfig(config.preSalePriceA, config.preSalePriceB, a_, b_);
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

        if (amountForAuction_ > MAX_SUPPLY - totalSupply()) revert TooMuchForAuction();

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

    // For marketing etc.
    function devMint(address[] calldata addresses, uint256[] calldata quantity) external onlyOwner {
        if (addresses.length != quantity.length) revert ArrayLengthNotMatch();

        uint256 totalMint;

        for (uint256 i = 0; i < addresses.length; i++) {
            totalMint += quantity[i];
        }

        if (totalSupply() + totalMint > amountForDevsAndPlatform) revert ReachMaxDevMintReserve();

        for (uint256 i = 0; i < addresses.length; i++) {
            _safeMint(addresses[i], quantity[i]);
        }
    }

    function setBaseURI(string calldata baseURI) public onlyOwner {
        _baseTokenURI = baseURI;
    }

    function setNotRevealedURI(string calldata notRevealedURI) external onlyOwner {
        _notRevealedURI = notRevealedURI;
    }

    function reveal(string calldata baseURI) external onlyOwner {
        if (revealed) revert AlreadyRevealed();
        if (initialrandomIndex != 0) revert AlreadySetStartingIndex();

        ChainLinkConfig memory config = chainLinkConfig;

        s_requestId = VRF_COORDINATOR.requestRandomWords(
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

        chainLinkConfig = ChainLinkConfig(
            keyhash_,
            config.s_subscriptionId,
            callbackGasLimit_,
            requestConfirmations_,
            config.numWords
        );
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert NonexistentToken();

        if (revealed == false) {
            return _notRevealedURI;
        }

        uint256 _initialrandomIndex = initialrandomIndex;

        if (_initialrandomIndex == 0) revert RandomnessRequestNotFinalized();

        string memory baseURI = _baseURI();
        uint256 collectionSize = MAX_SUPPLY;
        uint256 tailIndex = collectionSize - 1;

        uint256[] memory tempID = new uint256[](collectionSize);

        for (tailIndex; tailIndex > tokenId - 1; tailIndex--) {
            tempID[_initialrandomIndex] = (tempID[tailIndex] == 0 ? tailIndex + 1 : tempID[tailIndex]);

            _initialrandomIndex = (5 * _initialrandomIndex + 1) % tailIndex;
        }

        uint256 revealedID = (tempID[_initialrandomIndex] == 0 ? _initialrandomIndex + 1 : tempID[_initialrandomIndex]);

        return
            bytes(baseURI).length != 0
                ? string(abi.encodePacked(baseURI, revealedID.toString(), ".json"))
                : "baseuri not set correctly";
    }

    function isApprovedForAll(address _owner, address operator) public view override returns (bool) {
        // Whitelist OpenSea Proxy.
        
        if (address(PROXY_REGISTRY.proxies(_owner)) == operator) {
            return true;
        }

        return super.isApprovedForAll(_owner, operator);
    }

    function withdrawMoney() external nonReentrant {
        uint256 balance = address(this).balance;
        bool success;

        if (platform != address(0)) {
            (success, ) = platform.call{value: (balance * (platformRate)) / 100}("");
            if (!success) revert SendEtherFailed();
        }

        balance = address(this).balance;

        (success, ) = owner().call{value: balance}("");

        if (!success) revert TransferFailed();
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
        uint256 quantity,
        bytes memory signature
    ) public view returns (bool) {
        bytes32 rawMessageHash = _getMessageHash(_salt, _userAddress, quantity);

        return _recover(rawMessageHash, signature) == signer;
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function _getMessageHash(
        string calldata _salt,
        address _userAddress,
        uint256 quantity
    ) internal view returns (bytes32) {
        return keccak256(abi.encode(_salt, address(this), _userAddress, quantity));
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
        // s_randomWord = randomWords[0];

        uint256 _initialrandomIndex = (randomWords[0] % MAX_SUPPLY);

        // Prevent default sequence and for check VRF result
        if (_initialrandomIndex == 0) {
            unchecked {
                _initialrandomIndex = _initialrandomIndex + 1;
            }
        }

        initialrandomIndex = _initialrandomIndex;

        revealed = true;
    }
}
