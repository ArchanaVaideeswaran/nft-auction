import { ethers, upgrades } from 'hardhat';
import { Contract } from "ethers";
import * as fs from "fs";

async function main() {
  const [ owner ] = await ethers.getSigners();
    console.log(owner.address);

    const MIN_AUCTION_LENGTH_IN_SECONDS = 15 * 60;

    const Weth = await ethers.getContractFactory("WETH");
    const weth = await Weth.deploy();
    await weth.deployed();
    // storeContract(weth, "WETH");

    // const weth = "";
    console.log("WETH: ", weth.address);

    // Deploying
    console.log('Deploying DutchAuctionV1 .....');
    const DutchAuction = await ethers.getContractFactory("DutchAuctionV1");
    const instance = await upgrades.deployProxy(
      DutchAuction, 
      [weth.address, MIN_AUCTION_LENGTH_IN_SECONDS],
      {initializer: 'initialize'}
    );
    await instance.deployed();

    console.log('DutchAuctionV1 deployed at: ', instance.address);

    // Upgrading
    console.log('Upgrading DutchAuctionV1 to DutchAuctionV2 .....');
    const DutchAuctionV2 = await ethers.getContractFactory("DutchAuctionV2");
    const upgraded = await upgrades.upgradeProxy(instance.address, DutchAuctionV2);
    await upgraded.deployed();

    console.log('DutchAuctionV2 deployed at: ', upgraded.address);
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

main();