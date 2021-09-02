//SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "hardhat/console.sol";

import "../IBlockParties.sol";
import "../IPartyHost.sol";

contract SampleExchange is IPartyHost {
    address BlockPartiesContract = 0x5206e78b21Ce315ce284FB24cf05e0585A93B1d9; // TODO

    mapping(uint256 => Party) assets;

    enum State {
        OPEN,
        LISTED, // not used in this example, since resale is immediate
        SOLD,
        FAILED
    }

    struct Party {
        address tokenAddress;
        uint256 tokenId;
        State state;
        uint256 buyPrice;
    }

    constructor(address bp) {
        BlockPartiesContract = bp;
    }

    function createParty(
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _buyPrice
    ) external {
        IBlockParties bp = IBlockParties(BlockPartiesContract);
        uint256 id = bp.createParty();

        Party storage party = assets[id];
        party.tokenAddress = _tokenAddress;
        party.tokenId = _tokenId;
        party.buyPrice = _buyPrice;
    }

    function canDeposit(
        uint256 _assetId,
        address,
        uint256 _amount
    ) external view override returns (uint256) {
        require(
            assets[_assetId].state == State.OPEN,
            "Party is closed to new investments"
        );

        uint256 _rem = assets[_assetId].buyPrice - _amount;
        if (_rem < _amount) {
            return _rem;
        } else {
            return _amount;
        }
    }

    function canWithdraw(
        uint256 _assetId,
        address,
        uint256 _amount
    ) external view override returns (uint256) {
        require(
            assets[_assetId].state != State.LISTED,
            "Cannot withdraw while asset is listed for resale"
        );
        return _amount;
    }

    function buy(uint256 _assetId) external {
        IBlockParties bp = IBlockParties(BlockPartiesContract);
        bp.requestFunds(_assetId);
    }

    /// @dev simulate a resale at half the price of the buy
    function sell(uint256 _assetId) external {
        IBlockParties bp = IBlockParties(BlockPartiesContract);
        assets[_assetId].state = State.SOLD;
        bp.giveFunds{value: assets[_assetId].buyPrice / 2}(_assetId);
    }

    function giveFunds(uint256 _assetId) external payable override {
        // Empty by intention; just receive funds.
    }
}
