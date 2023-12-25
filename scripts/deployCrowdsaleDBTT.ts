import { ethers } from "hardhat";

async function deploy() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    const crowdsaleDBTT = await ethers.getContractFactory("CrowdfundingWithReferral");
    const contractCrowdfundingWithReferral = await crowdsaleDBTT.deploy();
    const deployedCrowdsaleDBTT = await contractCrowdfundingWithReferral.deployed();
    console.log(`DBTT deployed to: ${deployedCrowdsaleDBTT.address}`);
}

deploy()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
