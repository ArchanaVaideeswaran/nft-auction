import { ethers, upgrades } from 'hardhat';
import * as fs from "fs";

let proxy = '';

async function main() {
  const [ owner ] = await ethers.getSigners();
    console.log('Proxy admin (deployer): ', owner.address);
    await deploy();
    // await upgrade();
}
async function deploy() {
  // Deploying
  console.log('\nDeploying DutchAuctionV1 .....\n');

  const MIN_AUCTION_LENGTH_IN_SECONDS = 15 * 60;
  const DutchAuctionV1 = await ethers.getContractFactory("DutchAuctionV1");
  const instance = await upgrades.deployProxy(
    DutchAuctionV1, 
    [MIN_AUCTION_LENGTH_IN_SECONDS],
    {initializer: 'initialize'}
  );
  await instance.deployed();

  const implementationV1 = await upgrades.erc1967.getImplementationAddress(
    instance.address
  );
  const abiV1 = DutchAuctionV1.interface.format('json');
  storeProxy(instance.address, abiV1, 'DutchAuctionV1', 'goerli');

  console.log('DutchAuction Proxy deployed at: ', instance.address);
  console.log('DutchAuctionV1 implementation address: ', implementationV1);

  return instance.address;
}

async function upgrade() {
  // Upgrading
  console.log('\nUpgrading DutchAuctionV1 to DutchAuctionV2 .....\n');
  const DutchAuctionV2 = await ethers.getContractFactory("DutchAuctionV2");
  const upgraded = await upgrades.upgradeProxy(proxy, DutchAuctionV2);
  await upgraded.deployed();

  const implementationV2 = await upgrades.erc1967.getImplementationAddress(
    upgraded.address
  );
  const abiV2 = DutchAuctionV2.interface.format('json');
  storeProxy(upgraded.address, abiV2, 'DutchAuctionV2', 'goerli');

  console.log('DutchAuction Proxy deployed at: ', upgraded.address);
  console.log('DutchAuctionV2 implementation address: ', implementationV2);
}

function storeProxy(address: string, abi: any, name: string, network?: string) {
  // ----------------- MODIFIED FOR SAVING DEPLOYMENT DATA ----------------- //

  /**
   * @summary A build folder will be created in the root directory of the project
   * where the ABI, bytecode and the deployed address will be saved inside a JSON file.
   */

  const output = {
      address,
      abi,
  };

  if(network) {
    fs.mkdir(`./build/${network}/`, { recursive: true }, (err) => {
      if (err) console.error(err);
    });
    fs.writeFileSync(
      `./build/${network}/${name}.json`, 
      JSON.stringify(output)
    );
  }
  else {
    fs.mkdir(`./build/localhost/`, { recursive: true }, (err) => {
      if (err) console.error(err);
    });
    fs.writeFileSync(
      `./build/localhost/${name}.json`, 
      JSON.stringify(output)
    );
  }

  // ----------------------------------------------------------------------- //
}

main();