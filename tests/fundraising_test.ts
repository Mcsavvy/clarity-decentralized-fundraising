import {
  Clarinet,
  Tx,
  Chain,
  Account,
  types
} from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
  name: "Ensure that fundraising can be initialized",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    
    let block = chain.mineBlock([
      Tx.contractCall('fundraising', 'initialize', [types.uint(1000000), types.uint(144)], deployer.address)
    ]);
    
    assertEquals(block.receipts.length, 1);
    assertEquals(block.height, 2);
    block.receipts[0].result.expectOk().expectBool(true);
  },
});

Clarinet.test({
  name: "Ensure that users can contribute",
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
    
    assertEquals(block.receipts.length, 2);
    block.receipts[0].result.expectOk();
    block.receipts[1].result.expectOk().expectBool(true);
  },
});

Clarinet.test({
  name: "Ensure that minimum contribution is enforced",
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
    
    assertEquals(block.receipts.length, 2);
    block.receipts[0].result.expectOk();
    block.receipts[1].result.expectErr().expectUint(112); // ERR-MINIMUM-CONTRIBUTION-NOT-MET
  });

Clarinet.test({
  name: "Ensure that owner can set tiers",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    
    let block = chain.mineBlock([
      Tx.contractCall('fundraising', 'set-tier', [types.uint(1), types.uint(100000)], deployer.address),
      Tx.contractCall('fundraising', 'set-tier', [types.uint(2), types.uint(500000)], deployer.address)
    ]);
    
    assertEquals(block.receipts.length, 2);
    block.receipts[0].result.expectOk().expectBool(true);
    block.receipts[1].result.expectOk().expectBool(true);
    
    let tier1 = chain.callReadOnlyFn('fundraising', 'get-tier-amount', [types.uint(1)], deployer.address);
    let tier2 = chain.callReadOnlyFn('fundraising', 'get-tier-amount', [types.uint(2)], deployer.address);
    
    tier1.result.expectOk().expectUint(100000);
    tier2.result.expectOk().expectUint(500000);
  },
});

