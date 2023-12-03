import { ethers } from "hardhat";

async function deploy() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    const DBTT = await ethers.getContractFactory("VaultETH");
    const FACTORY = await DBTT.deploy();
    const deployedVault = await FACTORY.deployed();
    console.log(`DBTT deployed to: ${deployedVault.address}`);
}

deploy()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
