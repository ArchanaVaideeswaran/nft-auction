//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IWETH.sol";

contract DutchAuction is ERC721Holder, ReentrancyGuard {

    struct Listing {
        address seller;
        uint startPrice;
        uint endPrice;
        uint32 startTime;
        uint32 duration;
        address paymentToken;
    }

    uint public _minimumAuctionLengthInSeconds;
    address public owner;
    address public WETH;
    mapping(address => mapping(uint => Listing)) private _listings;

    event AuctionCreated(
        address indexed nft,
        uint tokenId,
        address indexed seller
    );
    event AuctionItemSold(
        address indexed nft,
        uint tokenId,
        address indexed seller,
        address indexed buyer,
        uint amount
    );
    event AuctionCancelled(
        address indexed nft,
        uint tokenId,
        address indexed seller
    );
    event UpdatedMinAuctionLength(uint lengthInSeconds);

    constructor(address weth, uint minimumAuctionLengthInSeconds) {
        owner = msg.sender;
        WETH = weth;
        setMinimumAuctionLength(minimumAuctionLengthInSeconds);
    }

    function createAuction(
        address nft,
        uint tokenId,
        uint startPrice,
        uint endPrice,
        uint32 startTime,
        uint32 duration,
        address paymentToken
    ) external nonReentrant {
        require(
            IERC165(nft).supportsInterface(type(IERC721).interfaceId),
            "Token contract does not support interface IERC721"
        );
        address tokenOwner = IERC721(nft).ownerOf(tokenId);
        require(
            msg.sender == tokenOwner || 
            IERC721(nft).isApprovedForAll(tokenOwner, msg.sender),
            "Caller is not owner or operator"
        );
        require(startPrice > 0, "Starting price too small");
        require(endPrice < startPrice, "End price must be < start price");
        require(
            paymentToken == WETH,
            "Payment token is not WETH"
        );
        require(
            startTime >= uint32(block.timestamp),
            "Start time must be >= block timestamp"
        );
        require(
            duration >= _minimumAuctionLengthInSeconds,
            "Duration must be greater than minimum auction duration"
        );

        Listing storage item = _listings[nft][tokenId];

        item.seller = msg.sender;
        item.startPrice = startPrice;
        item.endPrice = endPrice;
        item.startTime = startTime;
        item.duration = duration;
        item.paymentToken = paymentToken;

        _handleNftTransfer(nft, tokenId, msg.sender, address(this));

        emit AuctionCreated(nft, tokenId, msg.sender);
    }

    function buyAuctionItem(
        address nft,
        uint tokenId,
        uint amount
    ) external nonReentrant {
        Listing memory item = getListing(nft, tokenId);

        require(item.seller != address(0), "Auction item does not exist");
        require(msg.sender != item.seller, "Caller cannot be seller");

        uint currentAuctionPrice = getCurrentPrice(nft, tokenId);        
        require(amount >= currentAuctionPrice, "Cannot execute bid");

        delete _listings[nft][tokenId];

        _handlePayment(item.paymentToken, msg.sender, item.seller, amount);
        
        _handleNftTransfer(nft, tokenId, address(this), msg.sender);

        emit AuctionItemSold(nft, tokenId, item.seller, msg.sender, amount);
    }

    function cancelAuction(address nft, uint tokenId) external nonReentrant {
        Listing memory item = getListing(nft, tokenId);

        require(item.seller != address(0), "Auction item does not exists");
        require(item.seller == msg.sender, "Caller is not seller");

        delete _listings[nft][tokenId];

        _handleNftTransfer(nft, tokenId, address(this), item.seller);

        emit AuctionCancelled(nft, tokenId, item.seller);
    }

    function setMinimumAuctionLength(uint minimumAuctionLengthInSeconds) public {
        require(msg.sender == owner, "Caller not owner");
        require(
            minimumAuctionLengthInSeconds >= 15 minutes,
            "Auction length must be > 15 minutes"
        );
        _minimumAuctionLengthInSeconds = minimumAuctionLengthInSeconds;
        
        emit UpdatedMinAuctionLength(minimumAuctionLengthInSeconds);
    }

    function getListing(
        address nft,
        uint tokenId
    ) public view returns (Listing memory) {
        return _listings[nft][tokenId];
    }

    function getCurrentPrice(
        address nft,
        uint tokenId
    ) public view returns (uint) {
        Listing memory item = getListing(nft, tokenId);

        uint startTime = item.startTime;
        uint endTime = uint(item.startTime + item.duration);
        uint blockTimestamp = block.timestamp;

        require(startTime <= blockTimestamp, "Auction not started");
        require(endTime >= blockTimestamp, "Auction ended");

        uint currentAuctionPrice = item.startPrice - (
            ((item.startPrice - item.endPrice) * (blockTimestamp - startTime)) 
            / 
            (endTime - startTime)
        );

        return currentAuctionPrice;
    }

    function _handlePayment(
        address token,
        address from,
        address to,
        uint amount
    ) internal {
        IWETH(token).transferFrom(from, to, amount);
    }

    function _handleNftTransfer(
        address token,
        uint tokenId,
        address from,
        address to
    ) internal {
        IERC721(token).safeTransferFrom(from, to, tokenId);
    }
}