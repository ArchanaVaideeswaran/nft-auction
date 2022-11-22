//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./interfaces/IWETH.sol";

contract DutchAuctionV2 is 
    Initializable, 
    ERC721HolderUpgradeable, 
    ReentrancyGuardUpgradeable {

    struct Listing {
        address seller;
        address paymentToken;
        uint32 startTime;
        uint32 duration;
        uint startPrice;
        uint endPrice;
    }

    struct Bid {
        address bidder;
        address paymentToken;
        uint amount;
    }

    address public owner;
    address public weth;
    uint public minimumAuctionLengthInSeconds;
    mapping(address => mapping(uint => Listing)) private _listings;
    mapping (address => mapping(uint => mapping(address => Bid))) _bids;

    event AuctionCreated(
        address indexed nft,
        uint tokenId,
        address indexed seller
    );
    event BidPlaced(
        address indexed nft,
        uint tokenId,
        address indexed bidder,
        uint amount
    );
    event AuctionItemSold(
        address indexed nft,
        uint tokenId,
        address indexed seller,
        address indexed buyer,
        uint amount
    );
    event BidClaimed(
        address indexed nft,
        uint tokenId,
        address indexed bidder,
        uint amount
    );
    event AuctionCancelled(
        address indexed nft,
        uint tokenId,
        address indexed seller
    );
    event UpdatedMinAuctionLength(uint lengthInSeconds);

    function initialize(
        address _weth, 
        uint _minimumAuctionLengthInSeconds
    ) public initializer {
        __ReentrancyGuard_init();
        owner = msg.sender;
        weth = _weth;
        setMinimumAuctionLength(_minimumAuctionLengthInSeconds);
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
            "IERC721 not supported"
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
            paymentToken == weth,
            "Payment token is not WETH"
        );
        require(
            startTime >= uint32(block.timestamp) || startTime == 0,
            "Start time < block timestamp"
        );
        require(
            duration >= minimumAuctionLengthInSeconds,
            "Duration < min auction duration"
        );

        if(startTime == 0) {
            startTime = uint32(block.timestamp);
        }

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

    function placeBid(
        address nft,
        uint tokenId,
        uint amount
    ) external nonReentrant {
        Listing memory item = getListing(nft, tokenId);
        Bid memory bid = getBid(nft, tokenId, msg.sender);

        require(item.seller != address(0), "Auction item does not exist");
        require(msg.sender != item.seller, "Caller cannot be seller");
        require(bid.bidder == address(0) && bid.amount == 0, "Bid exists");
        require(amount >= item.endPrice, "Insufficient bid amount");

        bid.bidder = msg.sender;
        bid.paymentToken = item.paymentToken;
        bid.amount = amount;
        _bids[nft][tokenId][msg.sender] = bid;

        _handlePayment(item.paymentToken, msg.sender, address(this), amount);

        emit BidPlaced(nft, tokenId, msg.sender, amount);
    }

    function executeBid(
        address nft,
        uint tokenId
    ) external nonReentrant {
        Listing memory item = getListing(nft, tokenId);
        Bid memory bid = getBid(nft, tokenId, msg.sender);

        require(item.seller != address(0), "Auction item does not exist");
        require(bid.bidder != address(0), "Bid does not exist");
        require(bid.bidder == msg.sender, "Only bidder can execute bid");

        uint currentAuctionPrice = getCurrentPrice(nft, tokenId);
        require(bid.amount >= currentAuctionPrice, "Cannot execute bid");

        delete _listings[nft][tokenId];
        delete _bids[nft][tokenId][bid.bidder];

        _handlePayment(item.paymentToken, address(this), item.seller, bid.amount);
        _handleNftTransfer(nft, tokenId, address(this), msg.sender);

        emit AuctionItemSold(nft, tokenId, item.seller, msg.sender, bid.amount);
    }

    function claimBid(
        address nft,
        uint tokenId
    ) external nonReentrant {
        Listing memory item = getListing(nft, tokenId);
        Bid memory bid = getBid(nft, tokenId, msg.sender);

        require(item.seller == address(0), "Auction is active");
        require(bid.bidder != address(0), "Bid does not exist");
        require(bid.bidder == msg.sender, "Only bidder can claim bid");

        delete _bids[nft][tokenId][bid.bidder];

        _handlePayment(bid.paymentToken, address(this), bid.bidder, bid.amount);

        emit BidClaimed(nft, tokenId, bid.bidder, bid.amount);
    }

    function cancelAuction(address nft, uint tokenId) external nonReentrant {
        Listing memory item = getListing(nft, tokenId);

        require(item.seller != address(0), "Auction item does not exists");
        require(item.seller == msg.sender, "Caller is not seller");

        delete _listings[nft][tokenId];

        _handleNftTransfer(nft, tokenId, address(this), item.seller);

        emit AuctionCancelled(nft, tokenId, item.seller);
    }

    function setMinimumAuctionLength(uint _minimumAuctionLengthInSeconds) public {
        require(msg.sender == owner, "Caller not owner");
        require(
            _minimumAuctionLengthInSeconds >= 15 minutes,
            "Auction length < 15 minutes"
        );
        minimumAuctionLengthInSeconds = _minimumAuctionLengthInSeconds;
        
        emit UpdatedMinAuctionLength(minimumAuctionLengthInSeconds);
    }

    function getListing(
        address nft,
        uint tokenId
    ) public view returns (Listing memory) {
        return _listings[nft][tokenId];
    }

    function getBid(
        address nft,
        uint tokenId,
        address bidder
    ) public view returns (Bid memory) {
        return _bids[nft][tokenId][bidder];
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