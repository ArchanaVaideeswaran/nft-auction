//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts//interfaces/IERC165.sol";

contract Auction is ERC721Holder {
    
    // Type Declarations
    struct Listing {
        address payable seller;
        uint startingPrice;
        uint highestBid;
        address payable highestBidder;
        address paymentToken;
        uint32 startTime;
        uint32 duration;
        uint32 timeBuffer;
        uint96 ticSize;
    }

    struct Bid {
        address payable bidder;
        uint amount;
        address paymentToken;
    }

    // State Variables
    uint _listingId;
    mapping(address => mapping(uint => Listing)) _listings;
    mapping(address => mapping(uint => mapping(address => Bid))) _bids;

    // Events
    event AuctionCreated(
        address indexed nft,
        uint tokenId,
        address indexed seller
    );
    event BidPlaced(
        address indexed nft,
        uint tokenId,
        address indexed bidder,
        uint amount,
        bool extended
    );
    event BidClaimed(
        address indexed nft,
        uint tokenId,
        address indexed bidder,
        uint amount
    );

    // Modifiers

    // Constructor

    receive() external payable {}

    // External Functions

    function createAuction(
        address nft,
        uint tokenId,
        uint startingPrice,
        address paymentToken,
        uint32 startTime,
        uint32 duration,
        uint32 timeBuffer,
        uint96 ticSize
    ) external {
        require(
            IERC165(nft).supportsInterface(type(IERC721).interfaceId),
            "Token contract does not support IERC721"
        );
        address owner = IERC721(nft).ownerOf(tokenId);
        require(
            msg.sender == owner || 
            IERC721(nft).isApprovedForAll(owner, msg.sender),
            "Caller is not owner or operator"
        );
        require(startingPrice > 0, "Starting price too small");
        require(
            paymentToken == address(0) ||
            IERC165(paymentToken).supportsInterface(type(IERC20).interfaceId),
            "Payment token is neither zero (ETH) nor supports interface IERC20"
        );
        require(
            startTime >= uint32(block.timestamp) || startTime == 0,
            "Start time should be greater than or equal to block timestamp"
        );
        require(duration > 0, "Duration too small");
        require(timeBuffer < duration, "Time buffer too large");
        require(ticSize > 0, "Tic size too small");
        
        if(startTime == 0) {
            startTime = uint32(block.timestamp);
        }

        Listing storage item = _listings[nft][tokenId];

        item.seller = payable(msg.sender);
        item.startingPrice = startingPrice;
        item.paymentToken = paymentToken;
        item.startTime = startTime;
        item.duration = duration;
        item.timeBuffer = timeBuffer;
        item.ticSize = ticSize;

        IERC721(nft).safeTransferFrom(
            msg.sender,
            address(this),
            tokenId
        );

        emit AuctionCreated(nft, tokenId, msg.sender);
    }

    function bid(address nft, uint tokenId, uint amount) external {
        Listing storage item = _listings[nft][tokenId];
        uint32 blockTimeStamp = uint32(block.timestamp);

        require(item.seller != address(0), "Auction item does not exists");
        require(
            amount >= (item.highestBid + item.ticSize),
            "Minimum tic size not met"
        );
        require(
            item.startTime <= blockTimeStamp,
            "Auction not started"
        );
        require(
            blockTimeStamp < (item.startTime + item.duration),
            "Auction ended"
        );
        require(
            item.paymentToken != address(0),
            "Payment token is not ERC20"
        );

        Bid storage _bid = _bids[nft][tokenId][msg.sender];

        _bid.bidder = payable(msg.sender);
        _bid.amount += amount;
        _bid.paymentToken = item.paymentToken;

        item.highestBid = amount;
        item.highestBidder = payable(msg.sender);

        bool extended;
        uint32 timeRemaining = blockTimeStamp - item.startTime;

        if(timeRemaining <= item.timeBuffer) {
            item.duration += (item.timeBuffer - timeRemaining);
            extended = true;
        }

        IERC20(item.paymentToken).transferFrom(
            msg.sender,
            address(this),
            amount
        );

        emit BidPlaced(nft, tokenId, _bid.bidder, amount, extended);
    }

    function bidEth(address nft, uint tokenId) external payable {
        uint amount = msg.value;
        Listing storage item = _listings[nft][tokenId];
        uint32 blockTimeStamp = uint32(block.timestamp);

        require(item.seller != address(0), "Auction item does not exists");
        require(
            amount >= (item.highestBid + item.ticSize),
            "Minimum tic size not met"
        );
        require(
            item.startTime <= blockTimeStamp,
            "Auction not started"
        );
        require(
            blockTimeStamp < (item.startTime + item.duration),
            "Auction ended"
        );
        require(
            item.paymentToken == address(0),
            "Payment token is not ETH"
        );

        Bid storage _bid = _bids[nft][tokenId][msg.sender];

        _bid.bidder = payable(msg.sender);
        _bid.amount += amount;
        _bid.paymentToken = item.paymentToken;

        item.highestBid = amount;
        item.highestBidder = payable(msg.sender);

        bool extended;
        uint32 timeRemaining = blockTimeStamp - item.startTime;

        if(timeRemaining <= item.timeBuffer) {
            item.duration += (item.timeBuffer - timeRemaining);
            extended = true;
        }

        emit BidPlaced(nft, tokenId, _bid.bidder, amount, extended);
    }

    function settleAuction(address nft, uint tokenId) external {}

    function cancelAuction(address nft, uint tokenId) external {} 

    function claimBid(address nft, uint tokenId) external {
        Listing memory item = _listings[nft][tokenId];
        Bid memory _bid = _bids[nft][tokenId][msg.sender];

        require(_bid.amount > 0, "No active bids");
        require(
            item.highestBidder != msg.sender,
            "Highest bidder cannot claim bid"
        );

        if(_bid.paymentToken != address(0)) {
            IERC20(_bid.paymentToken).transferFrom(
                address(this),
                _bid.bidder,
                _bid.amount
            );
        } else {
            (bool succes, ) = payable(_bid.bidder).call{value: _bid.amount}("");
            require(succes, "ETH transfer failed");
        }

        delete _bids[nft][tokenId][msg.sender];

        emit BidClaimed(nft, tokenId, _bid.bidder, _bid.amount);
    }

    // Public Functions

    // Internal Functions

    // Private Fuctions
}