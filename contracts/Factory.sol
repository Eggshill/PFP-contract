// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./NFT.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

contract Factory is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    address public immutable ERC721A_IMPL;

    event CreateNFT(address indexed nftAddress);

    constructor() {
        __Ownable_init();
        ERC721A_IMPL = address(new NFT());
    }

    function createNFT(
        string memory name_,
        string memory symbol_,
        string memory contractURI_,
        uint256 maxBatchSize_,
        uint256 collectionSize_,
        uint256 amountForAuctionAndDev_,
        uint256 amountForDevs_
    ) public {
        // string[] memory infos = new string[](3);
        // infos[0] = _name;
        // infos[1] = _symbol;
        // infos[2] = _baseUri;

        address clone = ClonesUpgradeable.clone(ERC721A_IMPL);
        NFT(clone).initialize(
            name_,
            symbol_,
            contractURI_,
            maxBatchSize_,
            collectionSize_,
            amountForAuctionAndDev_,
            amountForDevs_
        );
        NFT(clone).transferOwnership(msg.sender);
        emit CreateNFT(clone);
    }
}
