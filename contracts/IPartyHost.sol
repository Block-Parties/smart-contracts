//SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

/// @title The interface implemented by every contract which interfaces with BlockParties.
interface IPartyHost {
    /// @notice Returns the max amount a given address is currently allowed to invest for
    ///         a particular asset, up to _amount.
    ///
    /// @dev To accept all deposits, simply return _amount.
    function canDeposit(
        uint256 _assetId,
        address _depositor,
        uint256 _amount
    ) external view returns (uint256);

    /// @notice Returns the max amount a given address is currently allowed to withdraw for
    ///         a particular asset, up to _amount. If _amount is greater than the amount the
    ///         has address has invested, the BlockParties contract will limit it to the amount
    ///         contributed thus far.
    ///
    /// @dev To accept full withdrawals, simply return _amount.
    function canWithdraw(
        uint256 _assetId,
        address _depositor,
        uint256 _amount
    ) external view returns (uint256);

    /// @dev this function is called by the BlockParties contract in response to a host
    ///       contract requesting its funds, with the total balance sent as msg.value.
    function giveFunds(uint256 _assetId) external payable;
}
