import { Avengers, Dummy, DutchAuction } from "../typechain-types";
const { ethers } = require("hardhat");
import { providers, utils } from 'ethers';
const { time } = require("@nomicfoundation/hardhat-network-helpers");
const Auction = require("../build/DutchAuction");
const WETH = require("../build/WETH");
const NFT = require("../build/AvengersNFT");
const axios = require('axios');

function toWei(value: string) {
    return ethers.utils.parseEther(value);
}

function toEther(value: string) {
    return ethers.utils.formatEther(value);
}

function executeQuery(query: string, event: string) {
    let url = 'http://localhost:3000/graphql';

    axios({
        url: url,
        method: "post",
        data: {
            query: query,
        },
    })
      .then((res: any) => {
        console.log(event, ': ', res.data.data);
      })
      .catch((err: any) => {
        console.log('\n----------------axios error----------------\n');
      });
}

function addUserToDatabase(address: string) {

    let user = `{
        address: "${address}"
    }`

    let query = `mutation { 
        addUser(newUserData: ${user}) { 
            id, 
            address 
        } 
    }`
    
    executeQuery(query, 'addUser');
}

function addBidToDatabase(bid: string) {

    let query = `mutation {
        addBid(bidData: ${bid}) {
            seller
            bids {
                bidder
            }
        }
    }`;

    // console.log(query);

    executeQuery(query, 'addBid');
}

async function main() {
    const MIN_AUCTION_LENGTH_IN_SECONDS = 15 * 60;
    // const FIVE_MINS_IN_SECONDS = 5 * 60;

    const accounts = await ethers.getSigners();
    const [ owner ] = accounts;

    // addUserToDatabase(owner.address);
    // console.log("----------User created in DB-----------");

    // console.log(accounts);

    const auction: DutchAuction = await ethers.getContractAt(Auction.abi, Auction.address);
    const nft = await ethers.getContractAt(NFT.abi, NFT.address);
    const weth = await ethers.getContractAt(WETH.abi, WETH.address);

    // auction.once('AuctionCreated', async (nft, tokenId, seller, tx) => {
    //     console.log('----------AuctionCreated event emitted----------');
    //     console.log(tx);
    //     let timestamp = (await tx.getBlock()).timestamp;
    //     console.log('Timestamp: ', timestamp);
    //     await new Promise((res) => {setTimeout((res) => {
    //         console.log('timeout');
    //     }, 3000)});
    //     const listing = await auction.getListing(nft, tokenId);
    //     console.log('Listing: ', listing);
    // });
    
    const provider = new providers.WebSocketProvider('http://localhost:8545');

    const filter = {
        address: auction.address,
        topics: [
            utils.id('buyAuctionItem(address,uint256,uint256)'),
        ],
    };
    provider.on('pending', async (pendingTx) => {
        console.log('pendingTx: ', pendingTx);
        provider.once(pendingTx, (tx) => {
            console.log('tx: ', tx);
        });
    });

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

    let amounts = [endPrice, startPrice];

    for(let i = 1, j = 1; i <= 1 && j <= 1; i++, j++) {
        let user = accounts[i];

        // addUserToDatabase(user.address);
        console.log("----------User created in DB-----------");

        tx = await nft.connect(owner).mint(user.address);
        await tx.wait();

        tokenId = j;

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
        tx = await tx.wait();

        console.log(tx.transactionHash);

        console.log("----------------auction created succesfully----------------");

        for(let k = 1; k <= 2; k++) {
            user = accounts[i + k];

            tx = await weth.connect(user).deposit({value: amounts[k - 1]});
            await tx.wait();

            tx = await weth.connect(user).approve(auction.address, amounts[k - 1]);
            await tx.wait();

            try {
                tx = await auction.connect(user).buyAuctionItem(
                    token,
                    tokenId,
                    amounts[k - 1]
                ).catch((e: any) => {throw(e);});
                tx = await tx.wait();
                console.log(
                    '----------------bid executed----------------\n', 
                    tx
                );
            } catch (error: any) {
                console.log('\n----------------error----------------\n');
                console.log(error.reason, '\n');
                
                tx = await tx.wait();
                console.log(
                    '----------------bid reverted----------------\n', 
                    tx
                );
                let timestamp = `${(
                    await ethers.provider.getBlock(tx.blockNumber)
                ).timestamp}`;

                let bid = `{
                    bidder: "${user.address}",
                    amount: ${parseFloat(toEther(amounts[k - 1]))},
                    nft: "${token}",
                    tokenId: "${tokenId.toString()}",
                    status: "CANCELLED",
                    blockNumber: ${tx.blockNumber},
                    transactionHash: "${tx.transactionHash}",
                    timestamp: ${parseInt(timestamp)}
                }`;
                // console.log(bid);

                // addBidToDatabase(bid);
            }
        }
    }

}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});