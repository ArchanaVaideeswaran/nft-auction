import { time } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { it } from "mocha";
import { Avengers, Dummy, DutchAuction, WETH } from "../typechain-types";

function toWei(value: string) {
    return ethers.utils.parseEther(value);
}

function toEther(value: string) {
    return ethers.utils.formatEther(value);
}

describe("Dutch Auction", () => {
    let owner: SignerWithAddress;
    let user1: SignerWithAddress;
    let user2: SignerWithAddress;
    let users: SignerWithAddress[];
    let weth: WETH;
    let auction: DutchAuction;
    let nft: Avengers;
    let dummy: Dummy;
    let MIN_AUCTION_LENGTH_IN_SECONDS = 15 * 60;

    before(async () => {
        [owner, user1, user2, ...users] = await ethers.getSigners();

        let Weth = await ethers.getContractFactory("WETH");
        weth = await Weth.deploy();
        await weth.deployed();

        let Auction = await ethers.getContractFactory("DutchAuction");
        let WETH = weth.address;
        auction = await Auction.deploy(WETH, MIN_AUCTION_LENGTH_IN_SECONDS);
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
        let startPrice;
        let endPrice
        let startTime;
        let duration;
        let paymentToken;

        it("should validate input params",async () => {
            token = nft.address;
            tokenId = 1;
            startPrice = toWei("10");
            endPrice = toWei("2");
            startTime = await time.latest();
            startTime += 5 * 60; // auction starts in 5 minutes from the previous block.
            duration = MIN_AUCTION_LENGTH_IN_SECONDS;
            paymentToken = weth.address;

            await expect(auction.createAuction(
                dummy.address, // passing invalid NFT contract address
                tokenId,
                startPrice,
                endPrice,
                startTime,
                duration,
                paymentToken
            )).to.be.rejectedWith(
                "Token contract does not support interface IERC721"
            );

             // "owner" is the owner of token ID 1 connecting "user1" throws error
            await expect(auction.connect(user1).createAuction(
                token,
                tokenId,
                startPrice,
                endPrice,
                startTime,
                duration,
                paymentToken
            )).to.be.rejectedWith(
                "Caller is not owner or operator"
            );

            await expect(auction.createAuction(
                token,
                0, // non existent token ID
                startPrice,
                endPrice,
                startTime,
                duration,
                paymentToken
            )).to.be.rejectedWith(
                "ERC721: invalid token ID"
            );

            await expect(auction.createAuction(
                token,
                tokenId,
                0, // start price should be > 0 for the price to fall eventually
                endPrice,
                startTime,
                duration,
                paymentToken
            )).to.be.rejectedWith(
                "Starting price too small"
            );

            await expect(auction.createAuction(
                token,
                tokenId,
                startPrice,
                toWei("12"), // start price is 10 end price is 12
                startTime,
                duration,
                paymentToken
            )).to.be.rejectedWith(
                "End price must be < start price"
            );

            await expect(auction.createAuction(
                token,
                tokenId,
                startPrice,
                endPrice,
                0, // start time cannot be 0 or less than block.timestamp
                duration,
                paymentToken
            )).to.be.rejectedWith(
                "Start time must be >= block timestamp"
            );

            await expect(auction.createAuction(
                token,
                tokenId,
                startPrice,
                endPrice,
                startTime,
                0, // duration should be greater than minimum auction duration
                paymentToken
            )).to.be.rejectedWith(
                "Duration must be greater than minimum auction duration"
            );

            await expect(auction.createAuction(
                token,
                tokenId,
                startPrice,
                endPrice,
                startTime,
                duration,
                dummy.address // payment token is not WETH address
            )).to.be.rejectedWith(
                "Payment token is not WETH"
            );
        });

        it("should create auction on valid inputs",async () => {
            token = nft.address;
            tokenId = 1;
            startPrice = toWei("10");
            endPrice = toWei("2");
            startTime = await time.latest();
            startTime += 5 * 60; // auction starts in 5 minutes from the previous block.
            duration = MIN_AUCTION_LENGTH_IN_SECONDS;
            paymentToken = weth.address;

            await nft.approve(auction.address, 1);

            await expect(auction.createAuction(
                token,
                tokenId,
                startPrice,
                endPrice,
                startTime,
                duration,
                paymentToken
            )).to.changeTokenBalances(nft, [owner, auction], [-1, 1]);
        })
    });

    describe("Function buy auction item", () => {
        // function parameters
        let token;
        let tokenId;
        let amount;
        let startTime;

        it("should validate input params",async () => {
            token = nft.address;
            tokenId = 1;
            amount = toWei("2");

            startTime = (await auction.getListing(token, tokenId)).startTime;

            await expect(auction.buyAuctionItem(
                token,
                2, // token Id 2 is not on auction
                amount
            )).to.be.rejectedWith(
                "Auction item does not exist"
            );

            // caller "owner" is auction item seller
            await expect(auction.buyAuctionItem(
                token,
                tokenId,
                amount
            )).to.be.rejectedWith(
                "Caller cannot be seller"
            );

            // auction has not started yet
            await expect(auction.connect(user1).buyAuctionItem(
                token,
                tokenId,
                amount
            )).to.be.rejectedWith(
                "Auction not started"
            );

            const FIVE_MINS_IN_SECONDS = 5 * 60;
            let increase = (
                startTime
                + FIVE_MINS_IN_SECONDS
            );
            await time.increaseTo(increase);

            await expect(auction.connect(user1).buyAuctionItem(
                token,
                tokenId,
                amount // amount too small at the given time
            )).to.be.rejectedWith(
                "Cannot execute bid"
            );

            increase += MIN_AUCTION_LENGTH_IN_SECONDS;
            await time.increaseTo(increase);

            // auction ended at the given time
            await expect(auction.connect(user1).buyAuctionItem(
                token,
                tokenId,
                amount
            )).to.be.rejectedWith(
                "Auction ended"
            );
        });

        it("should buy auction item on valid input", async () => {
            token = nft.address;
            tokenId = 1;
            amount = toWei("8");

            startTime = (await auction.getListing(token, tokenId)).startTime;
            const FIVE_MINS_IN_SECONDS = 5 * 60;
            let increase = (
                startTime
                + FIVE_MINS_IN_SECONDS
            );
            await time.increaseTo(increase);

            await weth.connect(user1).deposit({value: amount});
            await weth.connect(user1).approve(auction.address, amount);

            await expect(auction.connect(user1).buyAuctionItem(
                token,
                tokenId,
                amount
            )).to.changeTokenBalances(nft, [auction, user1], [-1, 1]);
        });
    });
});