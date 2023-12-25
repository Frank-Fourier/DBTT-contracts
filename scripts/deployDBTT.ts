import { ethers } from "hardhat";

async function deploy() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    const DBTT = await ethers.getContractFactory("DontBuyThisToken");
    const contractDBTT = await DBTT.deploy();
    const deployedDBTT = await contractDBTT.deployed();
    console.log(`DBTT deployed to: ${deployedDBTT.address}`);
}

deploy()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
