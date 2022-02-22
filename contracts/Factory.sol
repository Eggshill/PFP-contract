// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./NFT.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

contract Factory is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public immutable ERC721A_IMPL;

    address public platform;
    uint256 public platformRate;

    address public vrfCoordinatorAddress;
    address public linkAddress;
    bytes32 public keyHash;
    uint256 public fee;

    event CreateNFT(address indexed nftAddress);

    constructor(
        address platform_,
        uint256 platformRate_,
        address vrfCoordinatorAddress_,
        address linkAddress_,
        bytes32 keyHash_,
        uint256 fee_
    ) {
        __Ownable_init();
        ERC721A_IMPL = address(new NFT());

        platform = platform_;
        platformRate = platformRate_;

        vrfCoordinatorAddress = vrfCoordinatorAddress_;
        linkAddress = linkAddress_;
        keyHash = keyHash_;
        fee = fee_;
    }

    function createNFT(
        string memory name_,
        string memory symbol_,
        string memory notRevealedURI_,
        uint256 maxBatchSize_,
        uint256 collectionSize_,
        uint256 amountForDevsAndPlatform_,
        uint256 amountForPlatform__,
        address signer_
    ) public payable {
        require(amountForPlatform__ < amountForDevsAndPlatform_, "TOO MUCH FOR PLATFORM");

        address clonedNFT = ClonesUpgradeable.clone(ERC721A_IMPL);

        // [0: platformAddress, 1: signer, 2: vrfCoordinatorAddress, 3: linkAddress]
        address[4] memory relatedAddresses = [platform, signer_, vrfCoordinatorAddress, linkAddress];

        NFT(clonedNFT).initialize(
            name_,
            symbol_,
            notRevealedURI_,
            maxBatchSize_,
            collectionSize_,
            amountForDevsAndPlatform_,
            keyHash,
            fee,
            platformRate,
            relatedAddresses
        );
        NFT(clonedNFT).devMint(amountForDevsAndPlatform_, amountForPlatform__, msg.sender, platform);
        NFT(clonedNFT).transferOwnership(msg.sender);
        emit CreateNFT(clonedNFT);

        IERC20Upgradeable(linkAddress).safeTransfer(clonedNFT, fee);
    }

    function setPlatformParms(address payable platform_, uint256 platformRate_) public onlyOwner {
        require(platform_ != address(0), "PLATFORM ADDRESS IS ZERO");
        require(platformRate_ < 100, "WRONG RATE");

        platform = platform_;
        platformRate = platformRate_;
    }

    function withdrawToken(
        address token_,
        address destination_,
        uint256 amount_
    ) external onlyOwner {
        require(destination_ != address(0), "DESTINATION_CANNT_BE_0_ADDRESS");
        uint256 balance = IERC20Upgradeable(token_).balanceOf(address(this));
        require(balance >= amount_, "AMOUNT_CANNT_MORE_THAN_BALANCE");
        IERC20Upgradeable(token_).safeTransfer(destination_, amount_);
    }

    function withdrawEth(address destination_, uint256 amount_) external onlyOwner {
        require(destination_ != address(0), "DESTINATION_CANNT_BE_0_ADDRESS");

        (bool success, ) = destination_.call{value: amount_}("");
        require(success, "Failed to send Ether");
    }
}
