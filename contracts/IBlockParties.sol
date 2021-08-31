//SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

/// @title The interface for the central BlockParties contract.
interface IBlockParties {
    /// @notice Create a new party.
    /// @dev It's STRONGLY recommended to use the returned ID as each asset's ID, or at the very least kept alongside it.
    function createParty() external returns (uint256);

    /// @notice Returns the total balance in wei currently collected under the given Party.
    function getBalance(uint256 _partyId) external view returns (uint256);

    /// @notice Called by an IPartyHost contract to have the managed funds transferred over for use.
    function requestFunds(uint256 _partyId) external;

    /// @notice Called by an IPartyHost contract to return funds to the BlockParties contract.
    function giveFunds(uint256 _partyId) external payable;
}
