//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract EnglishAuction is ERC721Holder, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    struct Listing {
        address payable seller;
        uint startingPrice;
        Bid highestBid;
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

    mapping(address => mapping(uint => Listing)) private _listings;
    mapping(address => mapping(uint => mapping(address => Bid))) private _bids;

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
    event AuctionSettled(
        address indexed nft,
        uint tokenId,
        address indexed seller,
        address indexed bidder,
        uint amount
    );
    event AuctionCancelled(
        address indexed nft,
        uint tokenId,
        address indexed seller
    );

    function createAuction(
        address nft,
        uint tokenId,
        uint startingPrice,
        address paymentToken,
        uint32 startTime,
        uint32 duration,
        uint32 timeBuffer,
        uint96 ticSize
    ) external nonReentrant {
        require(
            IERC165(nft).supportsInterface(type(IERC721).interfaceId),
            "Token contract does not support interface IERC721"
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
            "Start time must be >= block timestamp"
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
        item.highestBid.paymentToken = paymentToken;
        item.startTime = startTime;
        item.duration = duration;
        item.timeBuffer = timeBuffer;
        item.ticSize = ticSize;

        _handleNftTransfer(nft, tokenId, msg.sender, address(this));

        emit AuctionCreated(nft, tokenId, msg.sender);
    }

    function bid(address nft, uint tokenId, uint amount) external payable nonReentrant {
        Listing storage item = _listings[nft][tokenId];
        uint32 blockTimeStamp = uint32(block.timestamp);

        require(item.seller != address(0), "Auction item does not exists");
        require(msg.sender != item.seller, "Caller cannot be seller");
        require(
            item.startTime <= blockTimeStamp,
            "Auction not started"
        );
        require(
            blockTimeStamp < (item.startTime + item.duration),
            "Auction ended"
        );
        if(item.highestBid.paymentToken == address(0)) {
            amount = msg.value;
        }
        require(
            amount >= (item.highestBid.amount + item.ticSize),
            "Minimum tic size not met"
        );

        Bid storage _bid = _bids[nft][tokenId][msg.sender];

        if(_bid.bidder == address(0)) {
            _bid.bidder = payable(msg.sender);
            _bid.amount = amount;
            _bid.paymentToken = item.highestBid.paymentToken;
        } else {
            _bid.amount += amount;
        }

        item.highestBid = _bid;

        bool extended;
        uint32 timeRemaining = blockTimeStamp - item.startTime;

        if(timeRemaining <= item.timeBuffer) {
            item.duration += (item.timeBuffer - timeRemaining);
            extended = true;
        }

        _handlePayment(_bid.paymentToken, msg.sender, address(this), amount);

        emit BidPlaced(nft, tokenId, _bid.bidder, amount, extended);
    }

    function settleAuction(address nft, uint tokenId) external nonReentrant {
        Listing memory item = getListing(nft, tokenId);
        Bid memory _bid = getBid(nft, tokenId, msg.sender);
        uint32 blockTimeStamp = uint32(block.timestamp);

        require(item.seller != address(0), "Auction item does not exists");
        require(
            blockTimeStamp > (item.startTime + item.duration),
            "Auction not ended"
        );
        require(item.highestBid.bidder == msg.sender, "Caller not highest bidder");

        delete _listings[nft][tokenId];
        delete _bids[nft][tokenId][msg.sender];

        _handleNftTransfer(nft, tokenId, address(this), item.highestBid.bidder);

        _handlePayment(_bid.paymentToken, address(this), item.seller, _bid.amount);

        emit AuctionSettled(nft, tokenId, item.seller, _bid.bidder, _bid.amount);
    }

    function cancelAuction(address nft, uint tokenId) external nonReentrant {
        Listing memory item = getListing(nft, tokenId);

        require(item.seller != address(0), "Auction item does not exists");
        require(item.seller == msg.sender, "Caller is not seller");
        require(item.highestBid.bidder == address(0), "Bid(s) exist");

        delete _listings[nft][tokenId];

        _handleNftTransfer(nft, tokenId, address(this), item.seller);

        emit AuctionCancelled(nft, tokenId, item.seller);
    } 

    function claimBid(address nft, uint tokenId) external nonReentrant {
        Listing memory item = getListing(nft, tokenId);
        Bid memory _bid = getBid(nft, tokenId, msg.sender);

        require(_bid.amount > 0, "No active bids");
        require(
            item.highestBid.bidder != msg.sender,
            "Highest bidder cannot claim bid"
        );

        delete _bids[nft][tokenId][msg.sender];

        _handlePayment(_bid.paymentToken, address(this), _bid.bidder, _bid.amount);

        emit BidClaimed(nft, tokenId, _bid.bidder, _bid.amount);
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

    function _handlePayment(
        address token,
        address from,
        address to,
        uint amount
    ) internal {
        if(token != address(0)) {
            IERC20(token).safeTransferFrom(from, to, amount);
        } else if(to != address(this)) {
            (bool success, ) = payable(to).call{value: amount}("");
            require(success, "ETH transfer failed");
        }
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