//SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "./IPartyHost.sol";
import "./IBlockParties.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/// @dev stub for interacting with ERC721 contracts.
interface ERC721 {
    function ownerOf(uint256 _tokenId) external view returns (address);
}

/// @dev stub for interacting with Wyvern Exchange.
/// For more details:
///     https://github.com/ProjectWyvern/wyvern-ethereum/blob/master/contracts/exchange/ExchangeCore.sol
///     https://github.com/ProjectWyvern/wyvern-ethereum/blob/master/contracts/exchange/Exchange.sol
interface IWyvernExchange {
    function atomicMatch_(
        address[14] calldata addrs,
        uint256[18] calldata uints,
        uint8[8] calldata feeMethodsSidesKindsHowToCalls,
        bytes calldata calldataBuy,
        bytes calldata calldataSell,
        bytes calldata replacementPatternBuy,
        bytes calldata replacementPatternSell,
        bytes calldata staticExtradataBuy,
        bytes calldata staticExtradataSell,
        uint8[2] calldata vs,
        bytes32[5] calldata rssMetadata
    ) external payable;

    function approveOrder_(
        address[7] calldata addrs,
        uint256[9] calldata uints,
        uint8 feeMethod,
        uint8 side,
        uint8 saleKind,
        uint8 howToCall,
        bytes calldata callData,
        bytes calldata replacementPattern,
        bytes calldata staticExtradata,
        bool orderbookInclusionDesired
    ) external;
}

/// @title Smart contract for buying and relisting assets using WyvernExchange,
///        using BlockParties to pool money and distribute profits.
contract WyvernExchange is Ownable, IPartyHost, IERC721Receiver {
    // paid out to owner
    uint8 internal constant FEE_PERCENT = 2;

    mapping(uint256 => Asset) assets;

    IBlockParties immutable bp;
    IWyvernExchange immutable ex;

    constructor(address blockPartiesContract, address wyvernExchangeContract) {
        bp = IBlockParties(blockPartiesContract);
        ex = IWyvernExchange(wyvernExchangeContract);
    }

    /////////////
    // Structs
    /////////////

    /// @notice Individual asset state.
    enum State {
        OPEN,
        BOUGHT,
        LISTED,
        FAILED,
        CLAIMED
    }

    /// @notice A single asset.
    struct Asset {
        State state;
        address tokenAddress;
        uint256 tokenId;
        uint256 buyPrice;
        uint256 resalePrice;
    }

    /// @notice Structure used by Wyvern Exchange contract
    /// @dev Destructured args sent to approveOrder_ on the Wyvern Exchange contract.
    struct wyvernApproveOrderData_ {
        address[7] addrs;
        uint256[9] uints;
        uint8 feeMethod;
        uint8 side;
        uint8 saleKind;
        uint8 howToCall;
        bytes callData;
        bytes replacementPattern;
        bytes staticExtradata;
        bool orderbookInclusionDesired;
    }

    /// @notice Structure used by Wyvern Exchange contract
    /// @dev Destructured args are sent to atomicMatch_ on the Wyvern Exchange contract.
    struct WyvernAtomicMatchData {
        address[14] addrs;
        uint256[18] uints;
        uint8[8] feeMethodsSidesKindsHowToCalls;
        bytes calldataBuy;
        bytes calldataSell;
        bytes replacementPatternBuy;
        bytes replacementPatternSell;
        bytes staticExtradataBuy;
        bytes staticExtradataSell;
        uint8[2] vs;
        bytes32[5] rssMetadata;
    }

    struct DecomposedCallData {
        uint32 function_signature;
        address seller_address;
        address buyer_address;
        uint256 token_id;
    }

    /////////////
    // Events
    /////////////

    event TokenReceived(address _tokenAddress, uint256 _tokenId);

    event TokenSold(uint256 _assetId, address _tokenAddress, uint256 _tokenId);

    /////////////
    // Functions
    /////////////

    /// @notice Create a new party and link it to a new BlockParties party.
    function createParty(
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _buyPrice,
        uint256 _resalePrice
    ) external {
        require(_buyPrice > 0, "buy price must be greater than 0");

        uint256 id = bp.createParty();

        Asset storage asset = assets[id];
        asset.tokenAddress = _tokenAddress;
        asset.tokenId = _tokenId;
        asset.buyPrice = _buyPrice;
        asset.resalePrice = _resalePrice;
    }

    /// @notice Returns amount that can be deposited.
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

    /// @notice Returns amount that can be withdrawn. Withdrawals are not accepted
    ///         once the asset has been relisted.
    function canWithdraw(
        uint256 _assetId,
        address,
        uint256 _amount
    ) external view override returns (uint256) {
        require(
            assets[_assetId].state != State.BOUGHT,
            "Withdrawals cannot be made while asset is relisted"
        );
        return _amount;
    }

    /// @dev implements IPartyHost interface.
    function giveFunds(uint256) external payable override {
        require(
            msg.sender == address(bp),
            "giveFunds may only be called by BlockParties contract"
        );
        // Empty by intention; just receive funds.
    }

    /// @notice Attempt to purchase the asset via WyvernExchange.
    /// @dev The actual transaction to be made is described entirely by the contents
    ///      of _data. Because of this, and because buy() can be called by anyone, the
    ///      following properties must be verified before sending the request to Wyvern:
    ///
    ///         - The buyer is this contract
    ///         - Token contract address matches asset's
    ///         - Token ID matches asset's
    ///
    ///      For further details on the contents of _data, refer to wyvern protocol's source.
    function buy(uint256 _assetId, WyvernAtomicMatchData memory _data)
        external
    {
        // check party has enough funds
        require(
            bp.getBalance(_assetId) == assets[_assetId].buyPrice,
            "insufficient funds pooled"
        );

        // sanity check
        require(_data.calldataBuy.length == 100, "The calldata is not correct");

        // unpack calldata
        DecomposedCallData memory callData;
        (
            callData.function_signature,
            callData.seller_address,
            callData.buyer_address,
            callData.token_id
        ) = abi.decode(_data.calldataBuy, (uint32, address, address, uint256));

        require(
            callData.buyer_address == address(this),
            "Mismatched buyer address; must be this contract"
        );

        require(
            callData.token_id == assets[_assetId].tokenId,
            "Mismatched token ID"
        );

        require(
            // determined via wyvern protocol source code.
            _data.addrs[4] == assets[_assetId].tokenAddress,
            "Mismatched token contract address"
        );

        // request funds from bp contract, and pass on the buy order
        bp.requestFunds(_assetId);
        try
            ex.atomicMatch_{value: assets[_assetId].buyPrice}(
                _data.addrs,
                _data.uints,
                _data.feeMethodsSidesKindsHowToCalls,
                _data.calldataBuy,
                _data.calldataSell,
                _data.replacementPatternBuy,
                _data.replacementPatternSell,
                _data.staticExtradataBuy,
                _data.staticExtradataSell,
                _data.vs,
                _data.rssMetadata
            )
        {
            assets[_assetId].state = State.BOUGHT;
        } catch {
            assets[_assetId].state = State.FAILED;
        }
    }

    /// @notice relist NFT on OpenSea.
    /// @dev same notes regarding verifying contents of _data in buy() apply here as well.
    function relist(uint256 _assetId, wyvernApproveOrderData_ memory _data)
        external
    {
        // sanity checks
        require(
            assets[_assetId].state == State.BOUGHT,
            "Asset has either not been bought, or was already listed"
        );
        require(
            ERC721(assets[_assetId].tokenAddress).ownerOf(
                assets[_assetId].tokenId
            ) == address(this),
            "Asset has not yet been transferred to contract"
        );
        require(_data.callData.length == 100, "The calldata is not correct");

        // unpack calldata
        DecomposedCallData memory callData;
        (
            callData.function_signature,
            callData.seller_address,
            callData.buyer_address,
            callData.token_id
        ) = abi.decode(_data.callData, (uint32, address, address, uint256));

        require(
            callData.seller_address == address(this),
            "Mismatched seller address; must be this contract"
        );

        require(
            callData.token_id == assets[_assetId].tokenId,
            "Mismatched token ID"
        );

        require(
            // determined via wyvern protocol source code.
            _data.addrs[4] == assets[_assetId].tokenAddress,
            "Mismatched token contract address"
        );

        // list asset
        ex.approveOrder_(
            _data.addrs,
            _data.uints,
            _data.feeMethod,
            _data.side,
            _data.saleKind,
            _data.howToCall,
            _data.callData,
            _data.replacementPattern,
            _data.staticExtradata,
            _data.orderbookInclusionDesired
        );

        assets[_assetId].state = State.LISTED;
    }

    /// @notice Return the funds to BlockParties contract so they can be claimed.
    ///         Requires that the party have either bought and resold the asset, or failed.
    function returnFunds(uint256 _assetId) external {
        // protect against multiple claims
        require(
            assets[_assetId].state != State.CLAIMED,
            "Funds have already been returned"
        );

        // in the case of failure, return funds for claiming refunds
        if (assets[_assetId].state == State.FAILED) {
            bp.giveFunds{value: assets[_assetId].buyPrice}(_assetId);
            assets[_assetId].state = State.CLAIMED;
            return;
        }

        // check if the asset has been sold by checking if we are no longer its holder
        if (
            assets[_assetId].state == State.LISTED &&
            ERC721(assets[_assetId].tokenAddress).ownerOf(
                assets[_assetId].tokenId
            ) !=
            address(this)
        ) {
            assets[_assetId].state = State.CLAIMED;

            // take fee
            uint256 fee = (assets[_assetId].resalePrice * FEE_PERCENT) / 100;
            (bool sent, ) = owner().call{value: fee}("");
            require(sent, "Failed to send Ether");

            // send proceeds back to BlockParties contract for claiming
            bp.giveFunds{value: assets[_assetId].resalePrice - fee}(_assetId);

            emit TokenSold(
                _assetId,
                assets[_assetId].tokenAddress,
                assets[_assetId].tokenId
            );
            return;
        }

        revert("Funds can only be returned after asset sold or failed");
    }

    /// @notice Manually mark a party as failed. Intended for special circumstances.
    function markFailed(uint256 _asetId) external onlyOwner {
        assets[_asetId].state = State.FAILED;
    }

    /// @notice Allows the contract to receive ERC721 tokens.
    function onERC721Received(
        address,
        address,
        uint256 _tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        emit TokenReceived(msg.sender, _tokenId);
        return this.onERC721Received.selector;
    }

    /////////////
    // Getters
    /////////////

    function getState(uint256 _assetId) external view returns (State) {
        return assets[_assetId].state;
    }

    function getBuyPrice(uint256 _assetId) external view returns (uint256) {
        return assets[_assetId].buyPrice;
    }

    function getResalePrice(uint256 _assetId) external view returns (uint256) {
        return assets[_assetId].resalePrice;
    }
}
