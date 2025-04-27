import {
  Clarinet,
  Tx,
  Chain,
  Account,
  types
} from 'https://deno.land/x/clarinet@v1.0.2/index.ts';
import { assertEquals, assertExists } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

// Comprehensive test suite for Decentralized Fundraising Contract

// Campaign Creation Tests
Clarinet.test({
  name: "create-campaign: Successfully create a campaign with valid parameters",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    
    let block = chain.mineBlock([
      Tx.contractCall('fundraising', 'create-campaign', 
        [
          types.uint(1000000),  // goal 
          types.uint(144),       // duration 
          types.uint(50),        // max-extension-blocks
          types.uint(100)        // min-contribution
        ], 
        deployer.address
      )
    ]);
    
    block.receipts[0].result.expectOk();
  }
});

Clarinet.test({
  name: "create-campaign: Reject campaign with zero goal",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    
    let block = chain.mineBlock([
      Tx.contractCall('fundraising', 'create-campaign', 
        [
          types.uint(0),         // zero goal 
          types.uint(144),       // duration 
          types.uint(50),        // max-extension-blocks
          types.uint(100)        // min-contribution
        ], 
        deployer.address
      )
    ]);
    
    block.receipts[0].result.expectErr().expectUint(1014); // ERR_INVALID_GOAL
  }
});

Clarinet.test({
  name: "create-campaign: Reject campaign with zero duration",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    
    let block = chain.mineBlock([
      Tx.contractCall('fundraising', 'create-campaign', 
        [
          types.uint(1000000),   // goal 
          types.uint(0),          // zero duration 
          types.uint(50),         // max-extension-blocks
          types.uint(100)         // min-contribution
        ], 
        deployer.address
      )
    ]);
    
    block.receipts[0].result.expectErr().expectUint(1010); // ERR_INVALID_DURATION
  }
});

// Contribution Tests
Clarinet.test({
  name: "contribute: Successful contribution within limits",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    
    let block = chain.mineBlock([
      Tx.contractCall('fundraising', 'create-campaign', 
        [
          types.uint(1000000),  // goal 
          types.uint(144),       // duration 
          types.uint(50),        // max-extension-blocks
          types.uint(100)        // min-contribution
        ], 
        deployer.address
      ),
      Tx.contractCall('fundraising', 'contribute', 
        [
          types.uint(0),         // campaign-id
          types.uint(500000)     // amount
        ], 
        wallet1.address
      )
    ]);
    
    block.receipts[1].result.expectOk().expectBool(true);
  }
});

Clarinet.test({
  name: "contribute: Reject contribution below minimum",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    
    let block = chain.mineBlock([
      Tx.contractCall('fundraising', 'create-campaign', 
        [
          types.uint(1000000),  // goal 
          types.uint(144),       // duration 
          types.uint(50),        // max-extension-blocks
          types.uint(500)        // min-contribution
        ], 
        deployer.address
      ),
      Tx.contractCall('fundraising', 'contribute', 
        [
          types.uint(0),         // campaign-id
          types.uint(100)        // amount less than min contribution
        ], 
        wallet1.address
      )
    ]);
    
    block.receipts[1].result.expectErr().expectUint(1008); // ERR_MINIMUM_CONTRIBUTION_NOT_MET
  }
});

// Withdrawal and Claim Tests
Clarinet.test({
  name: "claim-funds: Campaign creator can claim funds when goal is reached",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    
    let block = chain.mineBlock([
      Tx.contractCall('fundraising', 'create-campaign', 
        [
          types.uint(1000000),  // goal 
          types.uint(144),       // duration 
          types.uint(50),        // max-extension-blocks
          types.uint(100)        // min-contribution
        ], 
        deployer.address
      ),
      Tx.contractCall('fundraising', 'contribute', 
        [
          types.uint(0),         // campaign-id
          types.uint(1500000)    // amount exceeding goal
        ], 
        wallet1.address
      ),
      // Simulate block progression
      ...Array(200).fill(Tx.contractCall('fundraising', 'get-campaign-details', [types.uint(0)], deployer.address)),
      Tx.contractCall('fundraising', 'claim-funds', 
        [types.uint(0)], 
        deployer.address
      )
    ]);
    
    block.receipts[2 + 200].result.expectOk().expectBool(true);
  }
});

Clarinet.test({
  name: "claim-funds: Reject claim when goal not reached",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    
    let block = chain.mineBlock([
      Tx.contractCall('fundraising', 'create-campaign', 
        [
          types.uint(1000000),  // goal 
          types.uint(144),       // duration 
          types.uint(50),        // max-extension-blocks
          types.uint(100)        // min-contribution
        ], 
        deployer.address
      ),
      Tx.contractCall('fundraising', 'contribute', 
        [
          types.uint(0),         // campaign-id
          types.uint(500000)     // amount below goal
        ], 
        wallet1.address
      ),
      // Simulate block progression
      ...Array(200).fill(Tx.contractCall('fundraising', 'get-campaign-details', [types.uint(0)], deployer.address)),
      Tx.contractCall('fundraising', 'claim-funds', 
        [types.uint(0)], 
        deployer.address
      )
    ]);
    
    block.receipts[2 + 200].result.expectErr().expectUint(1003); // ERR_GOAL_NOT_REACHED
  }
});

// Authorization and Access Control Tests
Clarinet.test({
  name: "add-campaign-admin: Campaign creator can add campaign admin",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    
    let block = chain.mineBlock([
      Tx.contractCall('fundraising', 'create-campaign', 
        [
          types.uint(1000000),  // goal 
          types.uint(144),       // duration 
          types.uint(50),        // max-extension-blocks
          types.uint(100)        // min-contribution
        ], 
        deployer.address
      ),
      Tx.contractCall('fundraising', 'add-campaign-admin', 
        [
          types.uint(0),         // campaign-id
          types.principal(wallet1.address)  // new admin
        ], 
        deployer.address
      )
    ]);
    
    block.receipts[1].result.expectOk();
  }
});

Clarinet.test({
  name: "add-campaign-admin: Reject admin addition by non-creator",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    
    let block = chain.mineBlock([
      Tx.contractCall('fundraising', 'create-campaign', 
        [
          types.uint(1000000),  // goal 
          types.uint(144),       // duration 
          types.uint(50),        // max-extension-blocks
          types.uint(100)        // min-contribution
        ], 
        deployer.address
      ),
      Tx.contractCall('fundraising', 'add-campaign-admin', 
        [
          types.uint(0),         // campaign-id
          types.principal(wallet1.address)  // new admin
        ], 
          wallet1.address  // unauthorized sender
      )
    ]);
    
    block.receipts[1].result.expectErr().expectUint(1000); // ERR_UNAUTHORIZED
  }
});

// Emergency Pause Scenarios
Clarinet.test({
  name: "pause-contract: Only contract admin can pause",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    
    let block = chain.mineBlock([
      Tx.contractCall('fundraising', 'pause-contract', [], deployer.address),
      Tx.contractCall('fundraising', 'pause-contract', [], wallet1.address)
    ]);
    
    block.receipts[0].result.expectOk();
    block.receipts[1].result.expectErr().expectUint(1000); // ERR_UNAUTHORIZED
  }
});

Clarinet.test({
  name: "unpause-contract: Only contract admin can unpause",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const wallet1 = accounts.get('wallet_1')!;
    
    let block = chain.mineBlock([
      Tx.contractCall('fundraising', 'pause-contract', [], deployer.address),
      Tx.contractCall('fundraising', 'unpause-contract', [], wallet1.address)
    ]);
    
    block.receipts[0].result.expectOk();
    block.receipts[1].result.expectErr().expectUint(1000); // ERR_UNAUTHORIZED
  }
});

// Campaign Extension Tests
Clarinet.test({
  name: "extend-campaign-duration: Campaign creator can extend duration",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    
    let block = chain.mineBlock([
      Tx.contractCall('fundraising', 'create-campaign', 
        [
          types.uint(1000000),  // goal 
          types.uint(144),       // duration 
          types.uint(50),        // max-extension-blocks
          types.uint(100)        // min-contribution
        ], 
        deployer.address
      ),
      Tx.contractCall('fundraising', 'extend-campaign-duration', 
        [
          types.uint(0),         // campaign-id
          types.uint(30),         // additional blocks
          types.uint(50)          // max-extension-blocks
        ], 
        deployer.address
      )
    ]);
    
    block.receipts[1].result.expectOk();
  }
});

Clarinet.test({
  name: "extend-campaign-duration: Reject extension beyond max blocks",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    
    let block = chain.mineBlock([
      Tx.contractCall('fundraising', 'create-campaign', 
        [
          types.uint(1000000),  // goal 
          types.uint(144),       // duration 
          types.uint(50),        // max-extension-blocks
          types.uint(100)        // min-contribution
        ], 
        deployer.address
      ),
      Tx.contractCall('fundraising', 'extend-campaign-duration', 
        [
          types.uint(0),         // campaign-id
          types.uint(100),        // too many additional blocks
          types.uint(50)          // max-extension-blocks
        ], 
        deployer.address
      )
    ]);
    
    block.receipts[1].result.expectErr().expectUint(1011); // ERR_CAMPAIGN_EXTENDED_TOO_MUCH
  }
});

