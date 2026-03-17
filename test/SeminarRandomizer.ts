import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import hre, { network } from "hardhat";

describe("SeminarRandomizer", function () {
  async function deployRandomizerFixture() {
    const [admin, mentor1, mentor2, intern1, intern2, intern3, intern4, intern5, intern6] = await hre.ethers.getSigners();

    const SpeakerManager = await hre.ethers.getContractFactory("SpeakerManager");
    const speakerManager = await hre.upgrades.deployProxy(SpeakerManager, [admin.address], { initializer: 'initialize' });

    const SeminarManager = await hre.ethers.getContractFactory("SeminarManager");
    const seminarManager = await hre.upgrades.deployProxy(SeminarManager, [admin.address], { initializer: 'initialize' });

    const SeminarRandomizer = await hre.ethers.getContractFactory("SeminarRandomizer");
    const randomizer = await hre.upgrades.deployProxy(SeminarRandomizer, [admin.address], { initializer: 'initialize' });

    // Add participants
    await randomizer.connect(admin).addParticipant(mentor1.address, "Mentor 1", 1); // 1 = FULLTIME
    await randomizer.connect(admin).addParticipant(mentor2.address, "Mentor 2", 1);
    
    await randomizer.connect(admin).addParticipant(intern1.address, "Intern 1", 0); // 0 = INTERN
    await randomizer.connect(admin).addParticipant(intern2.address, "Intern 2", 0);
    await randomizer.connect(admin).addParticipant(intern3.address, "Intern 3", 0);
    await randomizer.connect(admin).addParticipant(intern4.address, "Intern 4", 0);
    await randomizer.connect(admin).addParticipant(intern5.address, "Intern 5", 0);
    await randomizer.connect(admin).addParticipant(intern6.address, "Intern 6", 0);

    return { randomizer, admin, mentor1, mentor2, intern1, intern2, intern3, intern4, intern5, intern6, speakerManager, seminarManager };
  }

  describe("Duck Race Process", function () {
    it("Should start and complete a race of 4 rounds", async function () {
      const { randomizer, admin } = await loadFixture(deployRandomizerFixture);

      const targetWeekStart = 1704067200; // Monday, Jan 1, 2024
      await randomizer.connect(admin).createRaceSession(targetWeekStart);

      let session = await randomizer.getSession(1);
      expect(session.status).to.equal(0); // PENDING

      // Round 1 (Fulltime)
      await randomizer.connect(admin).startNextRace(1);
      session = await randomizer.getSession(1);
      expect(session.status).to.equal(1); // RACING
      expect(session.currentRound).to.equal(1);
      expect(session.selectedMentor).to.not.equal(hre.ethers.ZeroAddress);

      // Round 2 (Intern 1)
      await randomizer.connect(admin).startNextRace(1);
      session = await randomizer.getSession(1);
      expect(session.currentRound).to.equal(2);
      expect(session.selectedInterns.length).to.equal(1);

      // Round 3 (Intern 2)
      await randomizer.connect(admin).startNextRace(1);

      // Round 4 (Intern 3) - Completes
      await randomizer.connect(admin).startNextRace(1);
      
      session = await randomizer.getSession(1);
      expect(session.status).to.equal(2); // COMPLETED
      expect(session.currentRound).to.equal(4);
      expect(session.selectedInterns.length).to.equal(3);

      const selectedTeam = await randomizer.getSelectedTeam(1);
      expect(selectedTeam.mentor).to.not.equal(hre.ethers.ZeroAddress);
      expect(selectedTeam.interns.length).to.equal(3);
    });

    it("Should apply cooldown logic correctly block next week selections", async function () {
      const { randomizer, admin } = await loadFixture(deployRandomizerFixture);

      const week1 = 1704067200; // Week 1
      const week2 = week1 + 7 * 24 * 60 * 60; // Week 2
      const week3 = week2 + 7 * 24 * 60 * 60; // Week 3

      // Session 1 for Week 1
      await randomizer.connect(admin).createRaceSession(week1);
      for(let i=0; i<4; i++) {
        await randomizer.connect(admin).startNextRace(1);
      }
      
      let team1 = await randomizer.getSelectedTeam(1);

      // Session 2 for Week 2
      await randomizer.connect(admin).createRaceSession(week2);
      let session2InternPool = await randomizer.getRemainingInternPool(2);
      let session2FulltimePool = await randomizer.getFulltimePool(2);

      // Team 1 members should not be in Week 2 pool (cooldown applied)
      expect(session2FulltimePool).to.not.include(team1.mentor);
      team1.interns.forEach((intern: string) => {
          expect(session2InternPool).to.not.include(intern);
      });

      // Finish Session 2
      for(let i=0; i<4; i++) {
        await randomizer.connect(admin).startNextRace(2);
      }

      // Session 3 for Week 3
      await randomizer.connect(admin).createRaceSession(week3);
      let session3InternPool = await randomizer.getRemainingInternPool(3);
      let session3FulltimePool = await randomizer.getFulltimePool(3);

      // Team 1 members SHOULD be in Week 3 pool again (cooldown expired)
      expect(session3FulltimePool).to.include(team1.mentor);
    });
  });
});
