//SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "./IPartyHost.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title BlockParties enables smart contracts to easily fractionalize anything.
contract BlockParties is Ownable {
    // Auto-incremented party ID
    uint256 id = 0;

    // Parties fractionalized by BlockParties
    mapping(uint256 => Party) parties;

    // Whitelisted services. Services must be whitelisted to use BlockParties
    mapping(address => bool) hostWhitelist;

    //////////////////////////////
    //  Structs
    //////////////////////////////

    /// @notice Reference to an asset managed by a party host.
    struct AssetRef {
        // The contract managing this asset.
        address hostAddress;
        // Unique asset ID used by the host contract.
        uint256 assetId;
    }

    /// @notice The core object in the fractionalization process.
    struct Party {
        // Refence to the asset being fractionalized.
        AssetRef assetRef;
        // The balance in wei associated with this party.
        uint256 balance;
        // A multiplier used to scale deposits and withdrawals made over time.
        //
        // Example scenario:
        //      a. Investor A deposits 1eth
        //      b. The party doubles its balance via a savvy investment
        //      c. Investor B deposits 1eth
        //
        //   though both investors have contributed 1eth, A is entitled to 2eth,
        //   whereas B is only entitled to 1eth.
        uint256 returnMultiplier;
        // Mapping between every party member and their contribution, in wei.
        mapping(address => uint256) stakes;
        // A running tally of the amount contributed, in wei.
        uint256 totalStakes;
    }

    //////////////////////////////
    //  Events
    //////////////////////////////

    /// @notice New party was created.
    event Created(uint256 partyId, address hostAddress, uint256 assetId);

    /// @notice An investor contributed to a party.
    event Deposited(uint256 partyId, address depositor, uint256 amount);

    /// @notice An investor withdrew from a party.
    event Withdrew(uint256 partyId, address withdrawer, uint256 amount);

    //////////////////////////////
    //  State Modifying Functions
    //////////////////////////////

    /// @notice Whitelist a contract for use with BlockParties.
    function whitelistHost(address _hostAddress) external {
        require(
            msg.sender == owner(),
            "Only BlockParties can whitelist a service at this time"
        );
        hostWhitelist[_hostAddress] = true;
    }

    /// @notice Create a new fractionalized party.
    /// @dev Should only be called by a (whitelisted) smart contract managing an asset.
    function createParty() external returns (uint256) {
        require(
            hostWhitelist[msg.sender],
            "This contract currently may not create parties"
        );

        Party storage party = parties[++id];
        party.assetRef.hostAddress = msg.sender;
        party.assetRef.assetId = id;
        party.returnMultiplier = 1_000_000_000;

        emit Created(id, msg.sender, id);

        return id;
    }

    /// @notice Deposit into a party, if permitted by the host.
    function deposit(uint256 _partyId) external payable {
        IPartyHost host = IPartyHost(parties[_partyId].assetRef.hostAddress);
        uint256 maxAcceptedDeposit = host.canDeposit(
            parties[_partyId].assetRef.assetId,
            msg.sender,
            msg.value
        );
        require(maxAcceptedDeposit > 0, "Party host rejected the deposit");
        require(
            msg.value >= maxAcceptedDeposit,
            "Party host's canDeposit function is incorrectly implemented"
        );

        parties[_partyId].stakes[msg.sender] +=
            maxAcceptedDeposit *
            parties[_partyId].returnMultiplier;
        parties[_partyId].totalStakes +=
            maxAcceptedDeposit *
            parties[_partyId].returnMultiplier;
        parties[_partyId].balance += maxAcceptedDeposit;

        uint256 excess = msg.value - maxAcceptedDeposit;

        if (excess > 0) {
            (bool sent, ) = msg.sender.call{value: excess}(""); // send excess back to depositor
            require(sent, "Failed to return excess Ether");
        }

        emit Deposited(_partyId, msg.sender, msg.value);
    }

    /// @notice Similar to deposit, but will revert if not all of msg.value can be deposited.
    function depositAtomic(uint256 _partyId) external payable {
        IPartyHost host = IPartyHost(parties[_partyId].assetRef.hostAddress);
        require(
            host.canDeposit(
                parties[_partyId].assetRef.assetId,
                msg.sender,
                msg.value
            ) == msg.value,
            "Party host rejected the deposit"
        );

        parties[_partyId].stakes[msg.sender] +=
            msg.value *
            parties[_partyId].returnMultiplier;
        parties[_partyId].totalStakes +=
            msg.value *
            parties[_partyId].returnMultiplier;
        parties[_partyId].balance += msg.value;

        emit Deposited(_partyId, msg.sender, msg.value);
    }

    /// @notice Withdraw from a party, if permitted by the host and past contributions.
    function withdraw(uint256 _partyId, uint256 _amount) external {
        uint256 senderStake = (parties[_partyId].stakes[msg.sender] *
            parties[_partyId].balance) / parties[_partyId].totalStakes;
        require(
            senderStake >= _amount,
            "The amount requested exceeds the sender's stake"
        );

        IPartyHost host = IPartyHost(parties[_partyId].assetRef.hostAddress);
        uint256 acceptableWithdrawalAmount = host.canWithdraw(
            parties[_partyId].assetRef.assetId,
            msg.sender,
            _amount
        );
        require(
            acceptableWithdrawalAmount > 0,
            "Party host rejected the withdrawal"
        );

        parties[_partyId].stakes[msg.sender] -=
            acceptableWithdrawalAmount /
            parties[_partyId].returnMultiplier;
        parties[_partyId].totalStakes -=
            acceptableWithdrawalAmount /
            parties[_partyId].returnMultiplier;
        parties[_partyId].balance -= acceptableWithdrawalAmount;

        (bool sent, ) = msg.sender.call{value: acceptableWithdrawalAmount}("");
        require(sent, "Failed to send Ether");

        emit Withdrew(_partyId, msg.sender, _amount);
    }

    /// @notice Similar to withdraw, but will revert if not all of msg.value can be withdrawn.
    function withdrawAtomic(uint256 _partyId, uint256 _amount) external {
        uint256 senderStake = (parties[_partyId].stakes[msg.sender] *
            parties[_partyId].balance) / parties[_partyId].totalStakes;
        require(
            senderStake >= _amount,
            "The amount requested exceeds the sender's balance"
        );

        IPartyHost host = IPartyHost(parties[_partyId].assetRef.hostAddress);
        require(
            host.canWithdraw(
                parties[_partyId].assetRef.assetId,
                msg.sender,
                _amount
            ) == _amount,
            "Party host rejected the withdrawal"
        );

        parties[_partyId].stakes[msg.sender] -=
            _amount /
            parties[_partyId].returnMultiplier;
        parties[_partyId].totalStakes -=
            _amount /
            parties[_partyId].returnMultiplier;
        parties[_partyId].balance -= _amount;

        (bool sent, ) = msg.sender.call{value: _amount}("");
        require(sent, "Failed to send Ether");

        emit Withdrew(_partyId, msg.sender, _amount);
    }

    /// @notice Called by a IPartyHost to request the party's balance be transferred for use.
    function requestFunds(uint256 _partyId) external {
        require(
            parties[_partyId].assetRef.hostAddress == msg.sender,
            "Only the party host can request these funds"
        );
        require(parties[_partyId].balance > 0, "Party balance is currently 0");

        IPartyHost host = IPartyHost(parties[_partyId].assetRef.hostAddress);
        host.giveFunds{value: parties[_partyId].balance}(
            parties[_partyId].assetRef.assetId
        );

        parties[_partyId].returnMultiplier *= parties[_partyId].balance;
        parties[_partyId].balance = 0;
    }

    /// @notice Called by a IPartyHost to transfer funds back, after which they can be redeemed by members.
    function giveFunds(uint256 _partyId) external payable {
        require(
            parties[_partyId].assetRef.hostAddress == msg.sender,
            "Caller is not a whitelisted Party host"
        );

        // add 1 to avoid division by zero.
        // considering these values are in wei, this should generally have a negligible effect on stakes.
        parties[_partyId].returnMultiplier /= (msg.value + 1);
        parties[_partyId].balance += msg.value;
    }

    //////////////////////////////
    //  Getters
    //////////////////////////////

    /// @notice Returns the party's balance in wei.
    function getBalance(uint256 _partyId) external view returns (uint256) {
        return parties[_partyId].balance;
    }

    /// @notice Returns equity % in the party * 1,000,000,000. e.g. 50% -> 0.5 * 1,000,000,000.
    function getGigaStake(uint256 _partyId, address _member)
        external
        view
        returns (uint256)
    {
        return
            (parties[_partyId].stakes[_member] * 1_000_000_000) /
            parties[_partyId].totalStakes;
    }

    /// @notice Returns the asset associated with a party, described as a contract address and asset id.
    function getAsset(uint256 _partyId)
        external
        view
        returns (address, uint256)
    {
        return (
            parties[_partyId].assetRef.hostAddress,
            parties[_partyId].assetRef.assetId
        );
    }

    /// @notice Returns whether the contract at hostAddress has been whitelisted by BlockParties.
    function isWhitelisted(address hostAddress) external view returns (bool) {
        return hostWhitelist[hostAddress];
    }
}
