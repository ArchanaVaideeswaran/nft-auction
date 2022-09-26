//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract DutchAuction is ERC721Holder, ReentrancyGuard {
    struct Listing {
        address payable seller;
        uint startPrice;
        uint endPrice;
        uint32 startTime;
        uint32 duration;
        address paymentToken;
    }

    mapping(address => mapping(uint => Listing)) private _listings;

    event AuctionCreated(
        address indexed nft,
        uint tokenId,
        address indexed seller
    );
    event AuctionSold(
        address indexed nft,
        uint tokenId,
        address indexed seller,
        address indexed buyer,
        uint amount
    );

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
        address owner = IERC721(nft).ownerOf(tokenId);
        require(
            msg.sender == owner || 
            IERC721(nft).isApprovedForAll(owner, msg.sender),
            "Caller is not owner or operator"
        );
        require(startPrice > 0, "Starting price too small");
        require(endPrice < startPrice, "End price must be < start price");
        require(
            paymentToken == address(0) ||
            IERC165(paymentToken).supportsInterface(type(IERC20).interfaceId),
            "Payment token is neither zero (ETH) nor supports interface IERC20"
        );
        require(
            startTime >= uint32(block.timestamp) || startTime == 0,
            "Start time must be >= block timestamp"
        );
        require(duration >= 15 minutes, "Auction duration must be >= 15 mins");

        Listing storage item = _listings[nft][tokenId];

        item.seller = payable(msg.sender);
        item.startPrice = startPrice;
        item.endPrice = endPrice;
        item.startTime = startTime;
        item.duration = duration;
        item.paymentToken = paymentToken;

        IERC721(nft).safeTransferFrom(
            msg.sender,
            address(this),
            tokenId
        );

        emit AuctionCreated(nft, tokenId, msg.sender);
    }

    function buyAuctionItem(
        address nft,
        uint tokenId,
        uint amount
    ) external nonReentrant {
        Listing memory item = getListing(nft, tokenId);

        require(item.seller != address(0), "Auction item does not exist");
        require(uint32(block.timestamp) >= item.startTime, "Auction not started");
        require(
            uint32(block.timestamp) < (item.startTime + item.duration),
            "Auction ended"
        );
        require(
            item.paymentToken != address(0),
            "Payment token is not ERC20"
        );

        uint elapsedTime = uint(uint32(block.timestamp) - item.startTime);
        uint currentPrice = getCurrentPrice(
            elapsedTime,
            item.duration,
            item.startPrice,
            item.endPrice
        );

        require(amount >= currentPrice, "Price too small");

        delete _listings[nft][tokenId];

        IERC721(nft).safeTransferFrom(
            address(this),
            msg.sender,
            tokenId
        );

        IERC20(item.paymentToken).transferFrom(
            msg.sender,
            item.seller,
            amount
        );

        emit AuctionSold(nft, tokenId, item.seller, msg.sender, amount);
    }

    function buyAuctionItemEth(
        address nft,
        uint tokenId
    ) external payable nonReentrant {
        Listing memory item = getListing(nft, tokenId);
        uint amount = msg.value;

        require(item.seller != address(0), "Auction item does not exist");
        require(uint32(block.timestamp) >= item.startTime, "Auction not started");
        require(
            uint32(block.timestamp) < (item.startTime + item.duration),
            "Auction ended"
        );
        require(
            item.paymentToken == address(0),
            "Payment token is not ETH"
        );

        uint elapsedTime = uint(uint32(block.timestamp) - item.startTime);
        uint currentPrice = getCurrentPrice(
            elapsedTime,
            item.duration,
            item.startPrice,
            item.endPrice
        );

        require(amount >= currentPrice, "Price too small");

        delete _listings[nft][tokenId];

        IERC721(nft).safeTransferFrom(
            address(this),
            msg.sender,
            tokenId
        );

        (bool succes, ) = payable(item.seller).call{value: amount}("");
        require(succes, "ETH transfer failed");

        emit AuctionSold(nft, tokenId, item.seller, msg.sender, amount);
    }

    function getCurrentPrice(
        uint elapsedTime,
        uint duration,
        uint startPrice,
        uint endPrice
    ) public pure returns (uint currentPrice) {
        currentPrice = ((startPrice - endPrice) * (elapsedTime)) / duration;
    }

    function getListing(
        address nft,
        uint tokenId
    ) public view returns (Listing memory) {
        return _listings[nft][tokenId];
    }
}