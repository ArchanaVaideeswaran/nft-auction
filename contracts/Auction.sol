//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
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

    // State Variables
    uint _listingId;
    mapping(address => mapping(uint => Listing)) _listings;
    mapping(address => mapping(uint => mapping(address => uint))) _bids;

    // Events
    event AuctionCreated(address indexed nft, uint tokenId, address indexed seller);

    // Modifiers

    // Constructor

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

    function bid(uint listingId, uint amount) external {}

    function bidEth(uint listingId) external payable {}

    function settleAuction(uint listingId) external {}

    function closeAuction(uint listingId) external {} 

    function claimBid(uint listingId) external {}

    // Public Functions

    // Internal Functions

    // Private Fuctions
}