//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract EnglishAuction is ERC721Holder, ReentrancyGuard {
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

        IERC721(nft).safeTransferFrom(
            msg.sender,
            address(this),
            tokenId
        );

        emit AuctionCreated(nft, tokenId, msg.sender);
    }

    function bid(address nft, uint tokenId, uint amount) external nonReentrant {
        Listing storage item = _listings[nft][tokenId];
        uint32 blockTimeStamp = uint32(block.timestamp);

        require(item.seller != address(0), "Auction item does not exists");
        require(
            amount >= (item.highestBid.amount + item.ticSize),
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
            item.highestBid.paymentToken != address(0),
            "Payment token is not ERC20"
        );

        Bid storage _bid = _bids[nft][tokenId][msg.sender];

        if(_bid.bidder == address(0)) {
            _bid.bidder = payable(msg.sender);
            _bid.amount += amount;
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

        IERC20(_bid.paymentToken).transferFrom(
            msg.sender,
            address(this),
            amount
        );

        emit BidPlaced(nft, tokenId, _bid.bidder, amount, extended);
    }

    function bidEth(address nft, uint tokenId) external payable nonReentrant {
        uint amount = msg.value;
        Listing storage item = _listings[nft][tokenId];
        uint32 blockTimeStamp = uint32(block.timestamp);

        require(item.seller != address(0), "Auction item does not exists");
        require(
            amount >= (item.highestBid.amount + item.ticSize),
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
            item.highestBid.paymentToken == address(0),
            "Payment token is not ETH"
        );

        Bid storage _bid = _bids[nft][tokenId][msg.sender];

        if(_bid.bidder == address(0)) {
            _bid.bidder = payable(msg.sender);
            _bid.amount += amount;
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

        IERC721(nft).safeTransferFrom(
            address(this),
            item.highestBid.bidder,
            tokenId
        );

        if(_bid.paymentToken != address(0)) {
            IERC20(_bid.paymentToken).transferFrom(
                address(this),
                item.seller,
                _bid.amount
            );
        } else {
            (bool succes, ) = payable(item.seller).call{value: _bid.amount}("");
            require(succes, "ETH transfer failed");
        }

        emit AuctionSettled(nft, tokenId, item.seller, _bid.bidder, _bid.amount);
    }

    function cancelAuction(address nft, uint tokenId) external nonReentrant {
        Listing memory item = getListing(nft, tokenId);

        require(item.seller != address(0), "Auction item does not exists");
        require(item.seller == msg.sender, "Caller is not seller");
        require(item.highestBid.bidder == address(0), "Bid(s) exist");

        delete _listings[nft][tokenId];

        IERC721(nft).safeTransferFrom(
            address(this),
            item.seller,
            tokenId
        );

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
}