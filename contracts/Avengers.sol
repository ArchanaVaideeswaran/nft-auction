// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract Avengers is ERC721{

    using Counters for Counters.Counter;
    Counters.Counter tokenId;
    address public owner;

    constructor() ERC721("Avengers NFT Collection", "AVG") {
        owner = msg.sender;
    }

    modifier  onlyOwner() {
        require(msg.sender == owner, "caller not owner");
        _;
    }
    
    function mint(address _to) public onlyOwner returns (uint256) {
        tokenId.increment();
        uint256 newTokenId = tokenId.current();
        _safeMint(_to, newTokenId);
        return newTokenId;
    }

}