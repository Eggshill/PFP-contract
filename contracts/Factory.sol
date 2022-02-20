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

    address public vrfCoordinatorAddress;
    address public linkAddress;
    bytes32 public keyHash;
    uint256 public fee;

    event CreateNFT(address indexed nftAddress);

    constructor(
        address vrfCoordinatorAddress_,
        address linkAddress_,
        bytes32 keyHash_,
        uint256 fee_
    ) {
        __Ownable_init();
        ERC721A_IMPL = address(new NFT());

        vrfCoordinatorAddress = vrfCoordinatorAddress_;
        linkAddress = linkAddress_;
        keyHash = keyHash_;
        fee = fee_;
    }

    function createNFT(
        string memory name_,
        string memory symbol_,
        string memory contractURI_,
        uint256 maxBatchSize_,
        uint256 collectionSize_,
        uint256 amountForAuctionAndDev_,
        uint256 amountForDevs_
    ) external onlyOwner {
        address clonedNFT = ClonesUpgradeable.clone(ERC721A_IMPL);
        NFT(clonedNFT).initialize(
            name_,
            symbol_,
            contractURI_,
            maxBatchSize_,
            collectionSize_,
            amountForAuctionAndDev_,
            amountForDevs_,
            vrfCoordinatorAddress,
            linkAddress,
            keyHash,
            fee
        );
        NFT(clonedNFT).devMint(amountForDevs_, msg.sender);
        NFT(clonedNFT).transferOwnership(msg.sender);
        emit CreateNFT(clonedNFT);

        IERC20Upgradeable(linkAddress).safeTransfer(clonedNFT, fee);
    }

    function withdrawLink(address destination_, uint256 amount_) external onlyOwner {
        require(destination_ != address(0), "DESTINATION_CANNT_BE_0_ADDRESS");
        uint256 balance = IERC20Upgradeable(linkAddress).balanceOf(address(this));
        require(balance >= amount_, "AMOUNT_CANNT_MORE_THAN_BALANCE");
        IERC20Upgradeable(linkAddress).safeTransfer(destination_, amount_);
    }
}
