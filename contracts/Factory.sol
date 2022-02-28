// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./NFT.sol";
// import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

contract Factory is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    // using SafeERC20Upgradeable for IERC20Upgradeable;

    address public erc721AImplementation;

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
        uint64 subscriptionId_
    ) {
        erc721AImplementation = address(new NFT());

        platform = platform_;
        platformRate = platformRate_;
        commission = commission_;

        vrfCoordinatorAddress = vrfCoordinatorAddress_;
        linkAddress = linkAddress_;
        keyHash = keyHash_;
        subscriptionId = subscriptionId_;
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
        address clonedNFT = ClonesUpgradeable.clone(erc721AImplementation);

        // [0: platformAddress, 1: signer, 2: vrfCoordinatorAddress, 3: linkAddress]
        address[4] memory relatedAddresses = [platform, signer_, vrfCoordinatorAddress, linkAddress];

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
        refundIfOver(commission);

        emit CreateNFT(clonedNFT);
    }

    function setPlatformParms(
        address payable platform_,
        uint256 platformRate_,
        uint256 commission_
    ) public onlyOwner {
        require(platform_ != address(0), "PLATFORM ADDRESS IS ZERO");
        require(platformRate_ < 100, "WRONG RATE");

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

    function withdrawEth(address destination_, uint256 amount_) external onlyOwner {
        require(destination_ != address(0), "DESTINATION_CANNT_BE_0_ADDRESS");

        (bool success, ) = destination_.call{value: amount_}("");
        require(success, "Failed to send Ether");
    }

    function refundIfOver(uint256 price) private {
        require(msg.value >= price, "Need to send more ETH.");
        if (msg.value > price) {
            (bool success, ) = payable(msg.sender).call{value: msg.value - price}("");
            require(success, "Failed to send Ether");
        }
    }
}
