import { Contract } from "ethers";
import { ethers } from "hardhat";
import * as fs from "fs";

async function main() {
    const [ owner ] = await ethers.getSigners();
    console.log(owner.address);

    const MIN_AUCTION_LENGTH_IN_SECONDS = 15 * 60;

    const Weth = await ethers.getContractFactory("WETH");
    const weth = await Weth.deploy();
    await weth.deployed();
    storeContract(weth, "WETH");

    // const weth = "";
    console.log("WETH: ", weth.address);

    const Auction = await ethers.getContractFactory("DutchAuction");
    const auction = await Auction.deploy(
        weth.address,
        MIN_AUCTION_LENGTH_IN_SECONDS
    );
    await auction.deployed();
    console.log("Dutch Auction: ", auction.address);

    storeContract(auction, "DutchAuction");

    const Nft = await ethers.getContractFactory("Avengers");
    const nft = await Nft.deploy();
    await nft.deployed();

    console.log("Avengers NFT: ", nft.address);

    storeContract(nft, "AvengersNFT");
}

function storeContract(contract: Contract, name: string) {
    // ----------------- MODIFIED FOR SAVING DEPLOYMENT DATA ----------------- //

    /**
     * @summary A build folder will be created in the root directory of the project
     * where the ABI, bytecode and the deployed address will be saved inside a JSON file.
     */

    const address = contract.address;
    const contractAbi = contract.interface.format('json').toString();
    const abi = JSON.parse(contractAbi);

    const output = {
        address,
        abi,
    };

    fs.mkdir('./build', { recursive: true }, (err) => {
        if (err) console.error(err);
    });

    fs.writeFileSync('./build/' + name + '.json', JSON.stringify(output));

    // ----------------------------------------------------------------------- //
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});