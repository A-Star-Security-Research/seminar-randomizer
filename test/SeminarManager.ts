import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import hre from "hardhat";

describe("SeminarManager", function () {
  async function deploySeminarManagerFixture() {
    const [admin, nonAdmin, speaker1] = await hre.ethers.getSigners();

    const SeminarManager = await hre.ethers.getContractFactory("SeminarManager");
    const seminarManager = await hre.upgrades.deployProxy(SeminarManager, [admin.address], { initializer: 'initialize' });

    return { seminarManager, admin, nonAdmin, speaker1 };
  }

  describe("Deployment", function () {
    it("Should set the right admin", async function () {
      const { seminarManager, admin } = await loadFixture(deploySeminarManagerFixture);
      const ADMIN_ROLE = await seminarManager.ADMIN_ROLE();
      expect(await seminarManager.hasRole(ADMIN_ROLE, admin.address)).to.equal(true);
    });
  });

  describe("Seminar Management", function () {
    it("Should create a new seminar", async function () {
      const { seminarManager, speaker1 } = await loadFixture(deploySeminarManagerFixture);

      const speakers = [speaker1.address];
      
      const nextId = await seminarManager.nextSeminarId();
      expect(nextId).to.equal(1);

      await expect(seminarManager.createSeminar("Intro to Web3", "Blockchain basics", "https://slides.com/intro", speakers))
        .to.emit(seminarManager, "SeminarCreated")
        .withArgs(1, "Intro to Web3", speakers);

      const seminarInfo = await seminarManager.getSeminar(1);
      expect(seminarInfo.title).to.equal("Intro to Web3");
      expect(seminarInfo.description).to.equal("Blockchain basics");
      expect(seminarInfo.slideLink).to.equal("https://slides.com/intro");
      expect(seminarInfo.speakers.length).to.equal(1);
      expect(seminarInfo.speakers[0]).to.equal(speaker1.address);
      
      const allSeminars = await seminarManager.getAllSeminars();
      expect(allSeminars.length).to.equal(1);
      expect(allSeminars[0]).to.equal(1);
    });

    it("Should update seminar info", async function () {
      const { seminarManager, speaker1 } = await loadFixture(deploySeminarManagerFixture);
      await seminarManager.createSeminar("Old Title", "Old Desc", "link", [speaker1.address]);

      await expect(seminarManager.updateSeminarInfo(1, "New Title", "New Desc"))
        .to.emit(seminarManager, "SeminarUpdated")
        .withArgs(1, "New Title");

      const seminarInfo = await seminarManager.getSeminar(1);
      expect(seminarInfo.title).to.equal("New Title");
      expect(seminarInfo.description).to.equal("New Desc");
    });

    it("Should update slide link", async function () {
      const { seminarManager, speaker1 } = await loadFixture(deploySeminarManagerFixture);
      await seminarManager.createSeminar("Title", "Desc", "old-link", [speaker1.address]);

      await expect(seminarManager.updateSlideLink(1, "new-link"))
        .to.emit(seminarManager, "SlideLinkUpdated")
        .withArgs(1, "new-link");

      const seminarInfo = await seminarManager.getSeminar(1);
      expect(seminarInfo.slideLink).to.equal("new-link");
    });
  });

  describe("Access Control", function () {
    it("Should revert if non-admin tries to modify seminars", async function () {
      const { seminarManager, nonAdmin, speaker1 } = await loadFixture(deploySeminarManagerFixture);

      await expect(seminarManager.connect(nonAdmin).createSeminar("T", "D", "L", [speaker1.address]))
        .to.be.revertedWith("SeminarManager: only admin");
    });
  });
});
