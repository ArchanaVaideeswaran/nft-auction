// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract Avengers is ERC721 , Ownable{

    using Counters for Counters.Counter;
    Counters.Counter tokenId;

    constructor() ERC721("Avengers NFT Collection", "AVG") {}

    function mint(address _to) public onlyOwner returns (uint256) {
        tokenId.increment();
        uint256 newTokenId = tokenId.current();
        _safeMint(_to, newTokenId);
        return newTokenId;
    }

}