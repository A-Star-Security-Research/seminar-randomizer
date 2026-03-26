import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import hre from "hardhat";

function getMondayStart(ts: number): number {
  const day = Math.floor(ts / 86400);
  const dayOfWeek = (day + 4) % 7;
  const offsetDaysFromMonday = (dayOfWeek + 6) % 7;
  const startOfDay = ts - (ts % 86400);
  return startOfDay - offsetDaysFromMonday * 86400;
}

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
    it("Should start and complete a race of 4 rounds (1 mentor, 3 interns)", async function () {
      const { randomizer, admin } = await loadFixture(deployRandomizerFixture);

      await randomizer.connect(admin).createRaceSession(1, 3);

      let session = await randomizer.getSession(1);
      expect(session.status).to.equal(0); // PENDING

      // Round 1 (Fulltime)
      await randomizer.connect(admin).startNextRace(1);
      session = await randomizer.getSession(1);
      expect(session.status).to.equal(1); // RACING
      expect(session.currentRound).to.equal(1);
      expect(session.selectedFulltimes.length).to.equal(1);

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
      expect(selectedTeam.fulltimes.length).to.equal(1);
      expect(selectedTeam.interns.length).to.equal(3);
    });

    it("Should apply cooldown logic correctly block next week selections", async function () {
      const { randomizer, admin } = await loadFixture(deployRandomizerFixture);

      // Session 1 for Week 1
      await randomizer.connect(admin).createRaceSession(1, 3);
      for(let i=0; i<4; i++) {
        await randomizer.connect(admin).startNextRace(1);
      }
      
      let team1 = await randomizer.getSelectedTeam(1);

      // Advance time by 1 week to simulate next session
      await time.increase(7 * 24 * 60 * 60);

      // Session 2 for Week 2
      await randomizer.connect(admin).createRaceSession(1, 3);
      let session2InternPool = await randomizer.getRemainingInternPool(2);
      let session2FulltimePool = await randomizer.getFulltimePool(2);

      // Team 1 members should not be in Week 2 pool (cooldown applied)
      expect(session2FulltimePool).to.not.include(team1.fulltimes[0]);
      team1.interns.forEach((intern: string) => {
          expect(session2InternPool).to.not.include(intern);
      });

      // Finish Session 2
      for(let i=0; i<4; i++) {
        await randomizer.connect(admin).startNextRace(2);
      }

      // Advance time by 1 week to simulate next session
      await time.increase(7 * 24 * 60 * 60);

      // Session 3 for Week 3
      await randomizer.connect(admin).createRaceSession(1, 3);
      let session3InternPool = await randomizer.getRemainingInternPool(3);
      let session3FulltimePool = await randomizer.getFulltimePool(3);

      // Team 1 members SHOULD be in Week 3 pool again (cooldown expired)
      expect(session3FulltimePool).to.include(team1.fulltimes[0]);
    });
  });

  describe("Edge Cases & Admin Functions", function () {
    it("Should allow pause and resume session transitions properly", async function () {
      const { randomizer, admin } = await loadFixture(deployRandomizerFixture);

      await randomizer.connect(admin).createRaceSession(1, 3);
      await randomizer.connect(admin).startNextRace(1); // RACING

      // Pause
      await expect(randomizer.connect(admin).pauseSession(1))
        .to.emit(randomizer, "SessionPaused")
        .withArgs(1);
      
      let session = await randomizer.getSession(1);
      expect(session.status).to.equal(3); // PAUSED

      // Cannot start race when paused
      await expect(randomizer.connect(admin).startNextRace(1))
        .to.be.revertedWith("Invalid status");

      // Resume
      await expect(randomizer.connect(admin).resumeSession(1))
        .to.emit(randomizer, "SessionResumed")
        .withArgs(1);

      session = await randomizer.getSession(1);
      expect(session.status).to.equal(1); // RACING
    });

    it("Should reset cooldowns when a session is cancelled", async function () {
      const { randomizer, admin } = await loadFixture(deployRandomizerFixture);

      await randomizer.connect(admin).createRaceSession(1, 3);
      // Run to completion to set cooldowns
      for(let i=0; i<4; i++) {
        await randomizer.connect(admin).startNextRace(1);
      }

      let session = await randomizer.getSession(1);
      expect(session.status).to.equal(2); // COMPLETED
      let team1 = await randomizer.getSelectedTeam(1);

      // Verify cooldown is set
      const targetWeekStart = Number(session.targetWeekStart);
      expect(await randomizer.isOnCooldown(team1.fulltimes[0], targetWeekStart + 7*24*60*60)).to.equal(true);

      // Cancel session
      await expect(randomizer.connect(admin).cancelSession(1))
        .to.emit(randomizer, "SessionCancelled")
        .withArgs(1);

      // Cooldown should be reset
      expect(await randomizer.isOnCooldown(team1.fulltimes[0], targetWeekStart + 7*24*60*60)).to.equal(false);
    });

    it("Should restrict updating seminar info and date to team members and admin", async function () {
      const { randomizer, admin, intern1, intern2, mentor2 } = await loadFixture(deployRandomizerFixture);

      await randomizer.connect(admin).createRaceSession(1, 3);
      for(let i=0; i<4; i++) {
        await randomizer.connect(admin).startNextRace(1);
      }

      let team1 = await randomizer.getSelectedTeam(1);
      const teamMentor = await hre.ethers.getSigner(team1.fulltimes[0]);
      const teamIntern = await hre.ethers.getSigner(team1.interns[0]);
      
      // Admin should be able to update
      await expect(randomizer.connect(admin).updateSeminarInfo(1, "Title", "Desc")).to.not.be.reverted;
      await expect(randomizer.connect(admin).updateSeminarDate(1, 1234567)).to.not.be.reverted;

      // Selected Mentor should be able to update
      await expect(randomizer.connect(teamMentor).updateSeminarInfo(1, "Title 2", "Desc 2")).to.not.be.reverted;
      
      // Selected Intern should be able to update
      await expect(randomizer.connect(teamIntern).updateSeminarDate(1, 9999999)).to.not.be.reverted;

      // Find someone who is NOT in the team
      const allParticipants = [intern1, intern2, mentor2];
      const outOfTeamMember = allParticipants.find(p => !team1.fulltimes.includes(p.address) && !team1.interns.includes(p.address));

      if (outOfTeamMember) {
        // Should reject if not admin or team member
        await expect(randomizer.connect(outOfTeamMember).updateSeminarInfo(1, "Hacked", "Hacked"))
          .to.be.revertedWith("Not authorized");
      }
    });

    it("Should complete a race even when the pool size is exactly the minimum (1 fulltime, 3 interns)", async function () {
      const { randomizer, admin, mentor1, mentor2, intern1, intern2, intern3, intern4, intern5, intern6 } = await loadFixture(deployRandomizerFixture);

      // Remove surplus participants to leave exactly 1 mentor and 3 interns
      await randomizer.connect(admin).removeParticipant(mentor2.address);
      await randomizer.connect(admin).removeParticipant(intern4.address);
      await randomizer.connect(admin).removeParticipant(intern5.address);
      await randomizer.connect(admin).removeParticipant(intern6.address);

      await randomizer.connect(admin).createRaceSession(1, 3);
      
      expect((await randomizer.getFulltimePool(1)).length).to.equal(1);
      expect((await randomizer.getRemainingInternPool(1)).length).to.equal(3);

      // Start rounds
      for(let i=0; i<4; i++) {
        await randomizer.connect(admin).startNextRace(1);
      }

      const session = await randomizer.getSession(1);
      expect(session.status).to.equal(2); // COMPLETED
      expect(session.currentRound).to.equal(4);

      const team = await randomizer.getSelectedTeam(1);
      expect(team.fulltimes[0]).to.equal(mentor1.address);
      expect(team.interns.length).to.equal(3);
    });
  });

  describe("Flexible Configuration", function () {
    it("Should support 2 fulltimes and 2 interns", async function () {
      const { randomizer, admin } = await loadFixture(deployRandomizerFixture);

      await randomizer.connect(admin).createRaceSession(2, 2);

      // Round 1 (Fulltime)
      await randomizer.connect(admin).startNextRace(1);
      // Round 2 (Fulltime)
      await randomizer.connect(admin).startNextRace(1);
      
      let session = await randomizer.getSession(1);
      expect(session.selectedFulltimes.length).to.equal(2);
      expect(session.selectedInterns.length).to.equal(0);
      expect(session.currentRound).to.equal(2);

      // Round 3 (Intern 1)
      await randomizer.connect(admin).startNextRace(1);
      // Round 4 (Intern 2) - Completes
      await randomizer.connect(admin).startNextRace(1);

      session = await randomizer.getSession(1);
      expect(session.status).to.equal(2); // COMPLETED
      expect(session.selectedInterns.length).to.equal(2);

      const team = await randomizer.getSelectedTeam(1);
      expect(team.fulltimes.length).to.equal(2);
      expect(team.interns.length).to.equal(2);
    });
  });

  describe("Week Scheduling and Sources", function () {
    it("Should create a session for an explicit week", async function () {
      const { randomizer, admin } = await loadFixture(deployRandomizerFixture);
      const now = await time.latest();
      const baseMonday = getMondayStart(Number(now));
      const week1 = baseMonday + 7 * 24 * 60 * 60;

      await randomizer.connect(admin).createRaceSessionForWeek(
        0,
        week1,
        1,
        3,
        false
      );

      const s1 = await randomizer.getSession(1);
      expect(Number(s1.targetWeekStart)).to.equal(week1);
    });

    it("Should validate participants against SpeakerManager when source contracts are set", async function () {
      const { randomizer, admin, speakerManager, seminarManager } = await loadFixture(deployRandomizerFixture);
      const [, , , , , , , , , outsider] = await hre.ethers.getSigners();

      await randomizer.connect(admin).setSourceContracts(
        await speakerManager.getAddress(),
        await seminarManager.getAddress()
      );

      await expect(
        randomizer.connect(admin).addParticipant(outsider.address, "Outsider", 0)
      ).to.be.revertedWith("Unknown speaker");

      await speakerManager.connect(admin).addSpeaker(outsider.address, "Outsider");
      await randomizer.connect(admin).addParticipant(outsider.address, "Outsider", 0);
    });

    it("Should allow admin to manually override selected team", async function () {
      const { randomizer, admin, mentor1, intern1, intern2, intern3 } = await loadFixture(deployRandomizerFixture);
      await randomizer.connect(admin).createRaceSession(1, 3);

      await randomizer.connect(admin).setSelectedTeam(
        1,
        [mentor1.address],
        [intern1.address, intern2.address, intern3.address],
        true
      );

      const session = await randomizer.getSession(1);
      expect(session.status).to.equal(2);
      const team = await randomizer.getSelectedTeam(1);
      expect(team.fulltimes[0]).to.equal(mentor1.address);
      expect(team.interns).to.deep.equal([intern1.address, intern2.address, intern3.address]);
    });
  });
});
