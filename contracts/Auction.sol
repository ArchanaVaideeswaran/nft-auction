//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;



contract Auction {
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
    mapping(uint => mapping(address => uint)) _bids;

    // Events

    // Modifiers

    // Constructor

    // External Functions

    function createAuction(
        address tokenContract,
        uint tokenId,
        address seller,
        uint startingPrice,
        address paymentToken,
        uint32 startTime,
        uint32 duration,
        uint32 timeBuffer,
        uint96 ticSize
    ) external {
        
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