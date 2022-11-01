const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const Auction = require("../build/DutchAuction");
const WETH = require("../build/WETH");
const NFT = require("../build/AvengersNFT");

function toWei(value: string) {
    return ethers.utils.parseEther(value);
}

async function main() {
    const MIN_AUCTION_LENGTH_IN_SECONDS = 15 * 60;
    // const FIVE_MINS_IN_SECONDS = 5 * 60;

    const accounts = await ethers.getSigners();
    const [ owner ] = accounts;

    // console.log(accounts);

    const auction = await ethers.getContractAt(Auction.abi, Auction.address);
    const nft = await ethers.getContractAt(NFT.abi, NFT.address);

    console.log("Auction contract: ", auction.address);
    console.log("NFT contract: ", nft.address);

    let token = nft.address;
    let tokenId;
    let startPrice = toWei("10");
    let endPrice = toWei("2");
    let startTime = 0;
    let duration = MIN_AUCTION_LENGTH_IN_SECONDS;
    let paymentToken = WETH.address;

    let tx;

    for(let i = 1; i <= 5; i++) {
        let user = accounts[i];

        tx = await nft.connect(owner).mint(user.address);
        await tx.wait();

        tokenId = i;

        console.log("tokenId: ", tokenId, " minted to: ", user.address);

        tx = await nft.connect(user).approve(auction.address, tokenId);
        await tx.wait();

        tx = await auction.connect(user).createAuction(
            token,
            tokenId,
            startPrice,
            endPrice,
            startTime,
            duration,
            paymentToken
        );
        await tx.wait();

        console.log(tx);

        console.log("auction created succesfully");
    }

}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});