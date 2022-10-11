import { time } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { Avengers, Dummy, EnglishAuction, WETH } from "../typechain-types";

function toWei(value: string) {
    return ethers.utils.parseEther(value);
}

function toEther(value: string) {
    return ethers.utils.formatEther(value);
}

describe("English Auction", () => {
    let owner: SignerWithAddress;
    let user1: SignerWithAddress;
    let user2: SignerWithAddress;
    let users: SignerWithAddress[];
    let weth: WETH;
    let auction: EnglishAuction;
    let nft: Avengers;
    let dummy: Dummy;
    const MIN_AUCTION_LENGTH_IN_SECONDS = 15 * 60;
    const FIVE_MINS_IN_SECONDS = 5 * 60;

    before(async () => {
        [owner, user1, user2, ...users] = await ethers.getSigners();

        let Weth = await ethers.getContractFactory("WETH");
        weth = await Weth.deploy();
        await weth.deployed();

        let Auction = await ethers.getContractFactory("EnglishAuction");
        let WETH = weth.address;
        auction = await Auction.deploy(WETH);
        await auction.deployed();

        let Nft = await ethers.getContractFactory("Avengers");
        nft = await Nft.deploy();
        await nft.deployed();

        await nft.mint(owner.address);
        await nft.mint(user1.address);

        let Dummy = await ethers.getContractFactory("Dummy");
        dummy = await Dummy.deploy();
        await dummy.deployed();
    });

    describe("Function create auction", () => {
        // function parameters
        let token;
        let tokenId;
        let startingPrice;
        let paymentToken;
        let startTime;
        let duration;
        let timeBuffer;
        let ticSize;
        it("should validate input parameters for creating auction", async () => {
            token = nft.address;
            tokenId = 1;
            startingPrice = toWei("5");
            paymentToken = weth.address;
            startTime = (await time.latest()) + FIVE_MINS_IN_SECONDS;
            duration = MIN_AUCTION_LENGTH_IN_SECONDS;
            timeBuffer = FIVE_MINS_IN_SECONDS;
            ticSize = toWei("1");
            
            await expect(auction.createAuction(
                dummy.address, // passing invalid NFT contract address
                tokenId,
                startingPrice,
                paymentToken,
                startTime,
                duration,
                timeBuffer,
                ticSize
            )).to.be.rejectedWith(
                "Token contract does not support interface IERC721"
            );

            await expect(auction.createAuction(
                token,
                2, // passing tokenId owned by user1
                startingPrice,
                paymentToken,
                startTime,
                duration,
                timeBuffer,
                ticSize
            )).to.be.rejectedWith(
                "Caller is not owner or operator"
            );

            await expect(auction.createAuction(
                token,
                tokenId,
                0, // passing 0 for starting price
                paymentToken,
                startTime,
                duration,
                timeBuffer,
                ticSize
            )).to.be.rejectedWith(
                "Starting price too small"
            );

            await expect(auction.createAuction(
                token,
                tokenId,
                startingPrice,
                dummy.address, // passing dummy address instead of WETH
                startTime,
                duration,
                timeBuffer,
                ticSize
            )).to.be.rejectedWith(
                "Payment token is not WETH"
            );

            await expect(auction.createAuction(
                token,
                tokenId,
                startingPrice,
                paymentToken,
                1, // passing start time less that block.timestamp
                duration,
                timeBuffer,
                ticSize
            )).to.be.rejectedWith(
                "Start time must be >= block timestamp"
            );

            await expect(auction.createAuction(
                token,
                tokenId,
                startingPrice,
                paymentToken,
                startTime,
                0, // passing 0 for auction duration
                timeBuffer,
                ticSize
            )).to.be.rejectedWith(
                "Duration too small"
            );

            await expect(auction.createAuction(
                token,
                tokenId,
                startingPrice,
                paymentToken,
                startTime,
                duration,
                duration, // passing auction duration for time buffer
                ticSize
            )).to.be.rejectedWith(
                "Time buffer too large"
            );

            await expect(auction.createAuction(
                token,
                tokenId,
                startingPrice,
                paymentToken,
                startTime,
                duration,
                timeBuffer,
                0 // passing 0 for tic size
            )).to.be.rejectedWith(
                "Tic size too small"
            );
        });

        it("should create auction on valid parameters", async () => {
            token = nft.address;
            tokenId = 1;
            startingPrice = toWei("5");
            paymentToken = weth.address;
            startTime = (await time.latest()) + FIVE_MINS_IN_SECONDS;
            duration = MIN_AUCTION_LENGTH_IN_SECONDS;
            timeBuffer = FIVE_MINS_IN_SECONDS;
            ticSize = toWei("1");

            await nft.approve(auction.address, tokenId);
            
            await expect(auction.createAuction(
                token,
                tokenId,
                startingPrice,
                paymentToken,
                startTime,
                duration,
                timeBuffer,
                ticSize
            )).to.changeTokenBalances(
                nft,
                [owner, auction],
                [-1, 1]
            );
        });
    });
});