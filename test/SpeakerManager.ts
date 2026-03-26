import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import hre from "hardhat";

describe("SpeakerManager", function () {
  async function deploySpeakerManagerFixture() {
    const [admin, nonAdmin, speaker1, speaker2] = await hre.ethers.getSigners();

    const SpeakerManager = await hre.ethers.getContractFactory("SpeakerManager");
    const speakerManager = await hre.upgrades.deployProxy(SpeakerManager, [admin.address], { initializer: 'initialize' });

    return { speakerManager, admin, nonAdmin, speaker1, speaker2 };
  }

  describe("Deployment", function () {
    it("Should set the right admin", async function () {
      const { speakerManager, admin } = await loadFixture(deploySpeakerManagerFixture);
      const ADMIN_ROLE = await speakerManager.ADMIN_ROLE();
      expect(await speakerManager.hasRole(ADMIN_ROLE, admin.address)).to.equal(true);
    });
  });

  describe("Speaker Management", function () {
    it("Should add a new speaker", async function () {
      const { speakerManager, speaker1 } = await loadFixture(deploySpeakerManagerFixture);

      await expect(speakerManager.addSpeaker(speaker1.address, "Alice"))
        .to.emit(speakerManager, "SpeakerAdded")
        .withArgs(speaker1.address, "Alice");

      const speakerInfo = await speakerManager.getSpeaker(speaker1.address);
      expect(speakerInfo.name).to.equal("Alice");
      expect(speakerInfo.speakerAddress).to.equal(speaker1.address);
      expect((await speakerManager.getAllSpeakers()).length).to.equal(1);
    });

    it("Should revert if speaker already exists", async function () {
      const { speakerManager, speaker1 } = await loadFixture(deploySpeakerManagerFixture);
      await speakerManager.addSpeaker(speaker1.address, "Alice");
      await expect(speakerManager.addSpeaker(speaker1.address, "Bob"))
        .to.be.revertedWith("SpeakerManager: speaker already exists");
    });

    it("Should update an existing speaker", async function () {
      const { speakerManager, speaker1 } = await loadFixture(deploySpeakerManagerFixture);
      await speakerManager.addSpeaker(speaker1.address, "Alice");

      await expect(speakerManager.updateSpeaker(speaker1.address, "Alice Updated"))
        .to.emit(speakerManager, "SpeakerUpdated")
        .withArgs(speaker1.address, "Alice Updated");

      const speakerInfo = await speakerManager.getSpeaker(speaker1.address);
      expect(speakerInfo.name).to.equal("Alice Updated");
    });

    it("Should remove a speaker", async function () {
      const { speakerManager, speaker1, speaker2 } = await loadFixture(deploySpeakerManagerFixture);
      await speakerManager.addSpeaker(speaker1.address, "Alice");
      await speakerManager.addSpeaker(speaker2.address, "Bob");

      await expect(speakerManager.removeSpeaker(speaker1.address))
        .to.emit(speakerManager, "SpeakerRemoved")
        .withArgs(speaker1.address);

      const speakerInfo = await speakerManager.getSpeaker(speaker1.address);
      expect(speakerInfo.name).to.equal("");
      
      const allSpeakers = await speakerManager.getAllSpeakers();
      expect(allSpeakers.length).to.equal(1);
      expect(allSpeakers[0]).to.equal(speaker2.address);
    });

    it("Should add a seminar to a speaker", async function () {
      const { speakerManager, speaker1 } = await loadFixture(deploySpeakerManagerFixture);
      await speakerManager.addSpeaker(speaker1.address, "Alice");
      
      const seminarId = 101;
      await expect(speakerManager.addSeminarToSpeaker(speaker1.address, seminarId))
        .to.emit(speakerManager, "SeminarAddedToSpeaker")
        .withArgs(speaker1.address, seminarId);

      const seminars = await speakerManager.getSpeakerSeminars(speaker1.address);
      expect(seminars.length).to.equal(1);
      expect(seminars[0]).to.equal(seminarId);
    });

    it("Should batch add and remove speakers", async function () {
      const { speakerManager, speaker1, speaker2 } = await loadFixture(deploySpeakerManagerFixture);

      await speakerManager.batchAddSpeakers(
        [speaker1.address, speaker2.address],
        ["Alice", "Bob"]
      );
      expect(await speakerManager.speakerExists(speaker1.address)).to.equal(true);
      expect(await speakerManager.speakerExists(speaker2.address)).to.equal(true);

      await speakerManager.batchRemoveSpeakers([speaker1.address, speaker2.address]);
      expect(await speakerManager.speakerExists(speaker1.address)).to.equal(false);
      expect(await speakerManager.speakerExists(speaker2.address)).to.equal(false);
    });
  });

  describe("Access Control", function () {
    it("Should revert if non-admin tries to modify speakers", async function () {
      const { speakerManager, nonAdmin, speaker1 } = await loadFixture(deploySpeakerManagerFixture);

      await expect(speakerManager.connect(nonAdmin).addSpeaker(speaker1.address, "Eve"))
        .to.be.revertedWith("SpeakerManager: only admin");
    });
  });
});
