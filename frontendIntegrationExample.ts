import { ethers, BrowserProvider, Signer, Contract } from "ethers";

// 1. Contract ABI Definition (Partial ABI with functions we need)
// In a real project, import this from your hardhat artifacts, e.g.:
// import SeminarRandomizerArtifact from "../artifacts/contracts/SeminarRandomizer.sol/SeminarRandomizer.json";
// const ABI = SeminarRandomizerArtifact.abi;
const ABI = [
  "function getSession(uint256 sessionId) view returns (tuple(uint256 sessionId, uint8 status, uint256 createdAt, uint256 targetWeekStart, uint256 preparationWeeks, uint256 requiredFulltimes, uint256 requiredInterns, address[] internPool, address[] fulltimePool, address[] selectedFulltimes, address[] selectedInterns, uint256 currentRound, string seminarTitle, string seminarDescription, uint256 seminarDate))",
  "function getSelectedTeam(uint256 sessionId) view returns (address[] fulltimes, address[] interns)",
  "function getUpcomingSessions() view returns (uint256[])",
  "function getPastSessions() view returns (uint256[])",
  "function getAllSessions() view returns (uint256[])",
  "function getParticipants(uint8 _pType) view returns (address[])",
  "function isOnCooldown(address participant, uint256 targetWeekStart) view returns (bool)",

  "function createRaceSession(uint256 _reqFulltimes, uint256 _reqInterns) returns (uint256 sessionId)",
  "function startNextRace(uint256 sessionId)",
  "function pauseSession(uint256 sessionId)",
  "function resumeSession(uint256 sessionId)",
  "function cancelSession(uint256 sessionId)",
  "function addParticipant(address _participant, string _name, uint8 _pType)",
  "function removeParticipant(address _participant)",
  "function updateSeminarInfo(uint256 sessionId, string _title, string _description)",
  "function updateSeminarDate(uint256 sessionId, uint256 _date)"
];

// 2. TypeScript Interfaces
export enum ParticipantType {
  INTERN = 0,
  FULLTIME = 1,
}

export enum SessionStatus {
  PENDING = 0,
  RACING = 1,
  COMPLETED = 2,
  PAUSED = 3,
  CANCELLED = 4,
}

export interface RaceSession {
  sessionId: bigint;
  status: SessionStatus;
  createdAt: bigint;
  targetWeekStart: bigint;
  preparationWeeks: bigint;
  requiredFulltimes: bigint;
  requiredInterns: bigint;
  internPool: string[];
  fulltimePool: string[];
  selectedFulltimes: string[];
  selectedInterns: string[];
  currentRound: bigint;
  seminarTitle: string;
  seminarDescription: string;
  seminarDate: bigint;
}

// 3. Service Class for Frontend Integration
export class SeminarRandomizerService {
  private contract: Contract;
  private provider: BrowserProvider | ethers.JsonRpcProvider;

  constructor(contractAddress: string, providerOrSigner: BrowserProvider | ethers.JsonRpcProvider | Signer) {
    // Initialize the contract instance using ethers v6
    this.contract = new ethers.Contract(contractAddress, ABI, providerOrSigner);
    this.provider = (providerOrSigner as any).provider || providerOrSigner;
  }

  // == READ FUNCTIONS ==

  /**
   * Fetch a specific session by ID
   */
  async getSession(sessionId: number | bigint): Promise<RaceSession> {
    const session = await this.contract.getSession(sessionId);
    
    // Ethers v6 returns a Result array which can be accessed by property names if they exist in the ABI tuple
    return {
      sessionId: session[0], // or session.sessionId
      status: Number(session[1]) as SessionStatus,
      createdAt: session[2],
      targetWeekStart: session[3],
      preparationWeeks: session[4],
      requiredFulltimes: session[5],
      requiredInterns: session[6],
      internPool: [...session[7]],
      fulltimePool: [...session[8]],
      selectedFulltimes: [...session[9]],
      selectedInterns: [...session[10]],
      currentRound: session[11],
      seminarTitle: session[12],
      seminarDescription: session[13],
      seminarDate: session[14],
    };
  }

  /**
   * Get the selected team (mentors + interns) for a given session
   */
  async getSelectedTeam(sessionId: number | bigint): Promise<{ fulltimes: string[]; interns: string[] }> {
    const result = await this.contract.getSelectedTeam(sessionId);
    return { fulltimes: [...result[0]], interns: [...result[1]] };
  }

  /**
   * Get all upcoming session IDs
   */
  async getUpcomingSessions(): Promise<bigint[]> {
    const sessions = await this.contract.getUpcomingSessions();
    return [...sessions];
  }

  /**
   * Fetch all participants of a specific type
   */
  async getParticipants(pType: ParticipantType): Promise<string[]> {
    const participants = await this.contract.getParticipants(pType);
    return [...participants];
  }

  /**
   * Check if a participant is on cooldown for a given target week
   */
  async isOnCooldown(participantAddr: string, targetWeekStart: number | bigint): Promise<boolean> {
    return this.contract.isOnCooldown(participantAddr, targetWeekStart);
  }

  // == WRITE FUNCTIONS (Requires Signer) ==

  /**
   * Add a new participant (Admin only)
   */
  async addParticipant(address: string, name: string, type: ParticipantType): Promise<ethers.ContractTransactionReceipt | null> {
    const tx = await this.contract.addParticipant(address, name, type);
    return tx.wait(); // Wait for the transaction to be mined
  }

  /**
   * Create a new race session for a specific target week with configurable fulltimes and interns (Admin only)
   */
  async createRaceSession(reqFulltimes: number, reqInterns: number): Promise<ethers.ContractTransactionReceipt | null> {
    const tx = await this.contract.createRaceSession(reqFulltimes, reqInterns);
    return tx.wait();
  }

  /**
   * Trigger the randomizer for the next step/round of the race (Admin only)
   */
  async startNextRace(sessionId: number | bigint): Promise<ethers.ContractTransactionReceipt | null> {
    const tx = await this.contract.startNextRace(sessionId);
    return tx.wait();
  }

  /**
   * Pause a racing session (Admin only)
   */
  async pauseSession(sessionId: number | bigint): Promise<ethers.ContractTransactionReceipt | null> {
    const tx = await this.contract.pauseSession(sessionId);
    return tx.wait();
  }

  /**
   * Update the title and description of the seminar (Team Member or Admin)
   */
  async updateSeminarInfo(sessionId: number | bigint, title: string, description: string): Promise<ethers.ContractTransactionReceipt | null> {
    const tx = await this.contract.updateSeminarInfo(sessionId, title, description);
    return tx.wait();
  }
}
