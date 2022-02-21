// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IMerkleDistributor {
    // Returns the merkle root of the merkle tree containing account balances available to claim.
    function merkleRoot() external view returns (bytes32);

    // Claim the given amount of the token to the given address. Reverts if the inputs are invalid.
    function preSalesMint(
        uint256 index,
        uint256 thisTimeMint,
        uint256 maxMint,
        bytes32[] calldata merkleProof
    ) external payable;

    // This event is triggered whenever a call to #claim succeeds.
    event PreSalesMint(uint256 indexed index, address indexed account, uint256 amount, uint256 maxMint);
}
