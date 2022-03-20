// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./NFT.sol";
// import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

error ZeroAddress();
error WrongRate();

contract Factory is Ownable, ReentrancyGuard {
    // using SafeERC20Upgradeable for IERC20Upgradeable;

    address public erc721AImplementation;
    address public proxyRegistryAddress;

    address public platform;
    uint256 public platformRate;
    uint256 public commission;

    address public vrfCoordinatorAddress;
    address public linkAddress;
    bytes32 public keyHash;
    uint64 public subscriptionId;

    event CreateNFT(address indexed nftAddress);

    constructor(
        address platform_,
        uint256 platformRate_,
        uint256 commission_,
        address vrfCoordinatorAddress_,
        address linkAddress_,
        bytes32 keyHash_,
        address proxyRegistryAddress_
    ) {
        erc721AImplementation = address(new NFT());

        proxyRegistryAddress = proxyRegistryAddress_;

        platform = platform_;
        platformRate = platformRate_;
        commission = commission_;

        vrfCoordinatorAddress = vrfCoordinatorAddress_;
        linkAddress = linkAddress_;
        keyHash = keyHash_;

        subscriptionId = VRFCoordinatorV2Interface(vrfCoordinatorAddress_).createSubscription();
    }

    function createNFT(
        string memory name_,
        string memory symbol_,
        string memory notRevealedURI_,
        uint256 maxPerAddressDuringMint_,
        uint256 collectionSize_,
        uint256 amountForDevsAndPlatform_,
        address signer_
    ) public payable {
        refundIfOver(commission);

        address clonedNFT = Clones.clone(erc721AImplementation);
        VRFCoordinatorV2Interface(vrfCoordinatorAddress).addConsumer(subscriptionId, clonedNFT);

        // [0: platformAddress, 1: signer, 2: vrfCoordinatorAddress, 3: linkAddress]
        address[5] memory relatedAddresses = [
            platform,
            signer_,
            vrfCoordinatorAddress,
            linkAddress,
            proxyRegistryAddress
        ];

        NFT(clonedNFT).initialize(
            name_,
            symbol_,
            notRevealedURI_,
            maxPerAddressDuringMint_,
            collectionSize_,
            amountForDevsAndPlatform_,
            keyHash,
            subscriptionId,
            platformRate,
            relatedAddresses
        );
        NFT(clonedNFT).transferOwnership(msg.sender);

        emit CreateNFT(clonedNFT);
    }

    function setPlatformParms(
        address payable platform_,
        uint256 platformRate_,
        uint256 commission_
    ) public onlyOwner {
        if (platform_ == address(0)) revert ZeroAddress();
        if (platformRate_ >= 100) revert WrongRate();

        platform = platform_;
        platformRate = platformRate_;
        commission = commission_;
    }

    function changeImplementation(address newImplementationAddress) public onlyOwner {
        erc721AImplementation = newImplementationAddress;
    }

    // function withdrawToken(
    //     address token_,
    //     address destination_,
    //     uint256 amount_
    // ) external onlyOwner {
    //     require(destination_ != address(0), "DESTINATION_CANNT_BE_0_ADDRESS");
    //     uint256 balance = IERC20Upgradeable(token_).balanceOf(address(this));
    //     require(balance >= amount_, "AMOUNT_CANNT_MORE_THAN_BALANCE");
    //     IERC20Upgradeable(token_).safeTransfer(destination_, amount_);
    // }

    function withdrawEth(address destination_, uint256 amount_) external onlyOwner nonReentrant {
        if (destination_ == address(0)) revert ZeroAddress();

        (bool success, ) = destination_.call{value: amount_}("");

        if (!success) revert SendEtherFailed();
    }

    function refundIfOver(uint256 price) private {
        if (msg.value < price) revert EtherNotEnough();
        if (msg.value > price) {
            (bool success, ) = payable(msg.sender).call{value: msg.value - price}("");

            if (!success) revert SendEtherFailed();
        }
    }
}
