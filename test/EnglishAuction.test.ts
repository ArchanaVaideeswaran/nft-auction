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
    let user3: SignerWithAddress;
    let users: SignerWithAddress[];
    let weth: WETH;
    let auction: EnglishAuction;
    let nft: Avengers;
    let dummy: Dummy;
    const MIN_AUCTION_LENGTH_IN_SECONDS = 15 * 60;
    const FIVE_MINS_IN_SECONDS = 5 * 60;

    before(async () => {
        [owner, user1, user2, user3, ...users] = await ethers.getSigners();

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
        await nft.mint(user2.address);

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
                "IERC721 not supported"
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
                "Start time < block timestamp"
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

            tokenId = 2;
            startTime += duration;
            await nft.connect(user1).approve(auction.address, tokenId);
            await expect(auction.connect(user1).createAuction(
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
                [user1, auction],
                [-1, 1]
            );

            tokenId = 3;
            startTime += duration;
            await nft.connect(user2).approve(auction.address, tokenId);
            await expect(auction.connect(user2).createAuction(
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
                [user2, auction],
                [-1, 1]
            );
        });
    });

    describe("Function bid", () => {
        // function parameters
        let token;
        let tokenId;
        let amount;
        let startTime;
        it("should validate input parameters for placing bid", async () => {
            token = nft.address;
            tokenId = 1;
            amount = toWei("7");

            await expect(auction.bid(
                token,
                4, // passing tokenId that is not on auction
                amount
            )).to.be.rejectedWith("Auction item does not exists");

             // caller is the seller
            await expect(auction.bid(
                token,
                tokenId,
                amount
            )).to.be.rejectedWith("Caller cannot be seller");

            // trying to bid before auction starts
            await expect(auction.connect(user1).bid(
                token,
                tokenId,
                amount
            )).to.be.rejectedWith("Auction not started");

            let increase = (await time.latest()) + FIVE_MINS_IN_SECONDS;
            await time.increaseTo(increase);

            await expect(auction.connect(user1).bid(
                token,
                tokenId,
                toWei("5.5") // minimum tic size set in 1 ether
            )).to.be.rejectedWith("Minimum tic size not met");

            increase = (await time.latest()) + MIN_AUCTION_LENGTH_IN_SECONDS;
            await time.increaseTo(increase);

            // placing bid after auction ends
            await expect(auction.connect(user1).bid(
                token,
                tokenId,
                amount
            )).to.be.rejectedWith("Auction ended");
        });

        it("should place bid on valid input parameters",async () => {
            token = nft.address;
            tokenId = 2;
            amount = toWei("7");

            startTime = (await auction.getListing(token, tokenId)).startTime;
            let currentTime = await time.latest();
            if(currentTime < startTime){
                let increase = startTime + FIVE_MINS_IN_SECONDS;
                await time.increaseTo(increase);
            }

            await weth.connect(user2).deposit({value: amount});
            await weth.connect(user2).approve(auction.address, amount);

            await expect(auction.connect(user2).bid(
                token,
                tokenId,
                amount
            )).to.changeTokenBalance(weth, auction, amount);

            amount = toWei("8");
            await weth.connect(user3).deposit({value: amount});
            await weth.connect(user3).approve(auction.address, amount);

            await expect(auction.connect(user3).bid(
                token,
                tokenId,
                amount
            )).to.changeTokenBalance(weth, auction, amount);

            tokenId = 3;
            amount = toWei("7");

            startTime = (await auction.getListing(token, tokenId)).startTime;
            currentTime = await time.latest();
            if(currentTime < startTime){
                let increase = startTime + FIVE_MINS_IN_SECONDS;
                await time.increaseTo(increase);
            }

            await weth.connect(user3).deposit({value: amount});
            await weth.connect(user3).approve(auction.address, amount);

            await expect(auction.connect(user3).bid(
                token,
                tokenId,
                amount
            )).to.changeTokenBalance(weth, auction, amount);
        })
    });

    describe("Function settle auction", () => {
        // function parameters
        let token;
        let tokenId;
        let endTime;
        let amount;
        let item;
        it("should validate input parameters for setteling auction", async () => {
            token = nft.address;
            tokenId = 2;

            await expect(auction.settleAuction(
                token,
                4 // passing tokenId that is not on auction
            )).to.be.rejectedWith("Auction item does not exists");

            await expect(auction.settleAuction(
                token,
                tokenId
            )).to.be.rejectedWith("Auction not ended");

            // auction ended for tokenId 1 in previous testcase
            // but no bids were placed
            await expect(auction.settleAuction(
                token,
                1
            )).to.be.rejectedWith("Caller not highest bidder");
        });

        it("should settle auction on valid parameters", async () => {
            token = nft.address;
            tokenId = 2;
            amount = toWei("8");
            item = await auction.getListing(token, tokenId);

            endTime = item.startTime + item.duration;
            let currentTime = await time.latest();
            if(currentTime < endTime){
                let increase = endTime + FIVE_MINS_IN_SECONDS;
                await time.increaseTo(increase);
            }

            await expect(auction.connect(user3).settleAuction(
                token,
                tokenId
            )).to.changeTokenBalance(
                weth, item.seller, amount
            ).and.changeTokenBalances(
                nft,
                [auction, user3],
                [-1, 1]
            );
        });
    });

    describe("Function cancel auction", () => {
        // function parameters
        let token;
        let tokenId;
        it("should validate input parameters for cancelling auction", async () => {
            token = nft.address;
            tokenId = 1;

            await expect(auction.cancelAuction(
                token,
                4 // passing tokenId that is not on auction
            )).to.be.rejectedWith("Auction item does not exists");

            // user1 in not the seller of tokenId 1
            await expect(auction.connect(user1).cancelAuction(
                token,
                tokenId // passing tokenId that is not on auction
            )).to.be.rejectedWith("Caller is not seller");

            // bid(s) exist for tokenId 3
            await expect(auction.connect(user2).cancelAuction(
                token,
                3
            )).to.be.rejectedWith("Bid(s) exist");
        });

        it("should cancel auction on valid parameters", async () => {
            token = nft.address;
            tokenId = 1;

            await expect(auction.cancelAuction(
                token,
                tokenId
            )).to.changeTokenBalances(
                nft,
                [auction, owner],
                [-1, 1]
            );
        });
    });

    describe("Function claim bid", () => {
        let token;
        let tokenId;
        it("should validate input parameters for claiming bid", async () => {
            token = nft.address;
            tokenId = 2;

            // owner has no active bids for tokenId 2
            await expect(auction.claimBid(
                token,
                tokenId
            )).to.be.rejectedWith("No active bids");

            // user3 is the highest bidder for tokenId 3
            await expect(auction.connect(user3).claimBid(
                token,
                3
            )).to.be.rejectedWith("Highest bidder cannot claim bid");
        });

        it("should claim bid on valid input parameters", async () => {
            token = nft.address;
            tokenId = 2;

            let amount = (await auction.getBid(
                token,
                tokenId,
                user2.address
            )).amount;

            await expect(auction.connect(user2).claimBid(
                token,
                tokenId
            )).to.changeTokenBalance(weth, user2, amount);
        });
    });
});