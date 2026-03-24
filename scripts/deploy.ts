import { ethers, upgrades } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // Deploy SpeakerManager
  console.log("Deploying SpeakerManager...");
  const SpeakerManager = await ethers.getContractFactory("SpeakerManager");
  const speakerManager = await upgrades.deployProxy(SpeakerManager, [deployer.address], {
    initializer: "initialize",
  });
  await speakerManager.waitForDeployment();
  const speakerManagerAddress = await speakerManager.getAddress();
  console.log("SpeakerManager Proxy deployed to:", speakerManagerAddress);

  // Deploy SeminarManager
  console.log("Deploying SeminarManager...");
  const SeminarManager = await ethers.getContractFactory("SeminarManager");
  const seminarManager = await upgrades.deployProxy(SeminarManager, [deployer.address], {
    initializer: "initialize",
  });
  await seminarManager.waitForDeployment();
  const seminarManagerAddress = await seminarManager.getAddress();
  console.log("SeminarManager Proxy deployed to:", seminarManagerAddress);

  // Deploy SeminarRandomizer
  console.log("Deploying SeminarRandomizer...");
  const SeminarRandomizer = await ethers.getContractFactory("SeminarRandomizer");
  const seminarRandomizer = await upgrades.deployProxy(SeminarRandomizer, [deployer.address], {
    initializer: "initialize",
  });
  await seminarRandomizer.waitForDeployment();
  const seminarRandomizerAddress = await seminarRandomizer.getAddress();
  console.log("SeminarRandomizer Proxy deployed to:", seminarRandomizerAddress);

  console.log("====================================");
  console.log("Deployment completed successfully!");
  console.log("SpeakerManager:    ", speakerManagerAddress);
  console.log("SeminarManager:    ", seminarManagerAddress);
  console.log("SeminarRandomizer: ", seminarRandomizerAddress);
  console.log("====================================");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
