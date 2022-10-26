const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const Auction = require("../build/DutchAuction");
const WETH = require("../build/WETH");
const NFT = require("../build/AvengersNFT");

function toWei(value) {
    return ethers.utils.parseEther(value);
}

async function main() {
    const MIN_AUCTION_LENGTH_IN_SECONDS = 15 * 60;
    const FIVE_MINS_IN_SECONDS = 5 * 60;

    const [owner, user1, user2 ] = await ethers.getSigners();

    const auction = await ethers.getContractAt(Auction.abi, Auction.address);
    const nft = await ethers.getContractAt(NFT.abi, NFT.address);

    let token = nft.address;
    let tokenId = 3;
    let startPrice = toWei("10");
    let endPrice = toWei("2");
    let startTime = 0;
    let duration = MIN_AUCTION_LENGTH_IN_SECONDS;
    let paymentToken = WETH.address;

    // listing tokenId 1 on auction owned by owner
    await nft.connect(user2).approve(auction.address, tokenId);

    let tx = await auction.connect(user2).createAuction(
        token,
        tokenId,
        startPrice,
        endPrice,
        startTime,
        duration,
        paymentToken
    );

    await tx.wait();

    console.log("auction created succesfully");

}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});