;; token-rewards
;; This contract enables campaign creators to integrate SIP-010 fungible tokens as rewards for fundraising campaign contributors.
;; It establishes a secure escrow system for token rewards, manages different reward tiers, and handles the distribution
;; of tokens to eligible contributors upon successful campaign completion.

;; Error constants
(define-constant ERR-UNAUTHORIZED u1)
(define-constant ERR-CAMPAIGN-INACTIVE u2)
(define-constant ERR-CAMPAIGN-ALREADY-EXISTS u3)
(define-constant ERR-CAMPAIGN-NOT-FOUND u4)
(define-constant ERR-TIER-ALREADY-EXISTS u5)
(define-constant ERR-TIER-NOT-FOUND u6)
(define-constant ERR-CAMPAIGN-STILL-ACTIVE u7)
(define-constant ERR-CAMPAIGN-FAILED u8)
(define-constant ERR-INSUFFICIENT-CONTRIBUTION u9)
(define-constant ERR-ALREADY-CLAIMED u10)
(define-constant ERR-TOKEN-TRANSFER-FAILED u11)
(define-constant ERR-INSUFFICIENT-TOKENS u12)
(define-constant ERR-INVALID-TOKEN-CONTRACT u13)
(define-constant ERR-INVALID-AMOUNT u14)

;; Data maps and variables

;; Campaigns map: stores metadata about each fundraising campaign
(define-map campaigns
  { campaign-id: uint }
  {
    creator: principal,
    token-contract: principal,    ;; Principal of the SIP-010 token used for rewards
    start-block: uint,
    end-block: uint,
    goal-amount: uint,
    raised-amount: uint,
    is-active: bool,
    is-successful: bool,
    total-tokens-allocated: uint  ;; Total tokens allocated for this campaign's rewards
  }
)

;; Reward tiers map: defines token reward tiers for each campaign
(define-map reward-tiers
  { campaign-id: uint, tier-id: uint }
  {
    min-contribution: uint,      ;; Minimum contribution amount to qualify for this tier
    token-amount: uint           ;; Amount of tokens rewarded at this tier
  }
)

;; Contributor rewards map: tracks rewards owed to contributors
(define-map contributor-rewards
  { campaign-id: uint, contributor: principal }
  {
    contribution-amount: uint,   ;; Total amount contributed
    tokens-allocated: uint,      ;; Amount of tokens allocated based on contribution
    claimed: bool                ;; Whether tokens have been claimed
  }
)

;; Private functions

;; Verify that tx-sender is the campaign creator
(define-private (is-campaign-creator (campaign-id uint))
  (let (
    (campaign-data (unwrap! (map-get? campaigns { campaign-id: campaign-id }) (err ERR-CAMPAIGN-NOT-FOUND)))
  )
    (if (is-eq tx-sender (get creator campaign-data))
      (ok true)
      (err ERR-UNAUTHORIZED)
    )
  )
)

;; Check if a campaign exists
(define-private (campaign-exists (campaign-id uint))
  (is-some (map-get? campaigns { campaign-id: campaign-id }))
)

;; Calculate token reward based on contribution amount and campaign tiers
(define-private (calculate-reward (campaign-id uint) (contribution-amount uint))
  (let (
    (tiers-list (get-campaign-tiers campaign-id))
    (highest-tier-reward (fold find-highest-qualifying-tier u0 tiers-list))
  )
    highest-tier-reward
  )
)

;; Helper function for fold to find highest qualifying tier reward
(define-private (find-highest-qualifying-tier (reward uint) (tier-tuple { tier-id: uint, min-contribution: uint, token-amount: uint }))
  (let (
    (min-contribution (get min-contribution tier-tuple))
    (token-amount (get token-amount tier-tuple))
  )
    (if (and (>= reward min-contribution) (> token-amount reward))
      token-amount
      reward
    )
  )
)

;; Transfer tokens using SIP-010 interface
(define-private (transfer-tokens (token-contract principal) (recipient principal) (amount uint))
  (contract-call? token-contract transfer amount tx-sender recipient none)
)

;; Read-only functions

;; Get campaign details
(define-read-only (get-campaign (campaign-id uint))
  (map-get? campaigns { campaign-id: campaign-id })
)

;; Get reward tier details
(define-read-only (get-reward-tier (campaign-id uint) (tier-id uint))
  (map-get? reward-tiers { campaign-id: campaign-id, tier-id: tier-id })
)

;; Get all reward tiers for a campaign
(define-read-only (get-campaign-tiers (campaign-id uint))
  ;; Note: This is a simplified implementation - in a real contract you would
  ;; either need to iterate through tier-ids or maintain a separate map of tiers per campaign
  ;; The implementation below assumes a maximum of 10 tiers per campaign for example
  (let (
    (tier-list (list))
    (tier-list (unwrap-panic (fold add-tier-if-exists tier-list (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10))))
  )
    tier-list
  )
)

;; Helper function to add tier to list if it exists
(define-private (add-tier-if-exists (result (list 10 { tier-id: uint, min-contribution: uint, token-amount: uint })) (tier-id uint))
  (let (
    (tier (map-get? reward-tiers { campaign-id: campaign-id, tier-id: tier-id }))
  )
    (if (is-some tier)
      (ok (unwrap! (as-max-len? (append result (merge { tier-id: tier-id } (unwrap-panic tier))) u10) (err u0)))
      (ok result)
    )
  )
)

;; Get contributor reward details
(define-read-only (get-contributor-reward (campaign-id uint) (contributor principal))
  (map-get? contributor-rewards { campaign-id: campaign-id, contributor: contributor })
)

;; Check if a contributor is eligible for rewards
(define-read-only (is-eligible-for-rewards (campaign-id uint) (contributor principal))
  (let (
    (campaign-data (unwrap-panic (get-campaign campaign-id)))
    (contributor-data (get-contributor-reward campaign-id contributor))
  )
    (and 
      (get is-successful campaign-data)
      (is-some contributor-data)
      (> (get contribution-amount (unwrap-panic contributor-data)) u0)
      (not (get claimed (unwrap-panic contributor-data)))
    )
  )
)

;; Public functions

;; Create a new campaign with token rewards
(define-public (create-campaign 
  (campaign-id uint) 
  (token-contract principal) 
  (start-block uint) 
  (end-block uint) 
  (goal-amount uint)
  (total-tokens-allocated uint))
  
  (let (
    (current-block block-height)
  )
    ;; Validate inputs
    (asserts! (> end-block start-block) (err ERR-INVALID-AMOUNT))
    (asserts! (>= start-block current-block) (err ERR-INVALID-AMOUNT))
    (asserts! (> goal-amount u0) (err ERR-INVALID-AMOUNT))
    (asserts! (> total-tokens-allocated u0) (err ERR-INVALID-AMOUNT))
    
    ;; Check campaign doesn't already exist
    (asserts! (not (campaign-exists campaign-id)) (err ERR-CAMPAIGN-ALREADY-EXISTS))
    
    ;; Transfer tokens from creator to contract for escrow
    (asserts! 
      (is-ok (contract-call? token-contract transfer total-tokens-allocated tx-sender (as-contract tx-sender) none))
      (err ERR-TOKEN-TRANSFER-FAILED)
    )
    
    ;; Create campaign entry
    (map-set campaigns
      { campaign-id: campaign-id }
      {
        creator: tx-sender,
        token-contract: token-contract,
        start-block: start-block,
        end-block: end-block,
        goal-amount: goal-amount,
        raised-amount: u0,
        is-active: true,
        is-successful: false,
        total-tokens-allocated: total-tokens-allocated
      }
    )
    
    (ok true)
  )
)

;; Add a reward tier to a campaign
(define-public (add-reward-tier (campaign-id uint) (tier-id uint) (min-contribution uint) (token-amount uint))
  (begin
    ;; Verify sender is campaign creator
    (try! (is-campaign-creator campaign-id))
    
    ;; Check campaign exists and is still active
    (let (
      (campaign-data (unwrap! (get-campaign campaign-id) (err ERR-CAMPAIGN-NOT-FOUND)))
    )
      (asserts! (get is-active campaign-data) (err ERR-CAMPAIGN-INACTIVE))
      (asserts! (>= (get end-block campaign-data) block-height) (err ERR-CAMPAIGN-INACTIVE))
      (asserts! (not (is-some (get-reward-tier campaign-id tier-id))) (err ERR-TIER-ALREADY-EXISTS))
      
      ;; Validate tier inputs
      (asserts! (> min-contribution u0) (err ERR-INVALID-AMOUNT))
      (asserts! (> token-amount u0) (err ERR-INVALID-AMOUNT))
      
      ;; Create the tier
      (map-set reward-tiers
        { campaign-id: campaign-id, tier-id: tier-id }
        { min-contribution: min-contribution, token-amount: token-amount }
      )
      
      (ok true)
    )
  )
)

;; Record a contribution and allocate appropriate token rewards
(define-public (record-contribution (campaign-id uint) (contributor principal) (amount uint))
  (let (
    (campaign-data (unwrap! (get-campaign campaign-id) (err ERR-CAMPAIGN-NOT-FOUND)))
    (current-block block-height)
    (existing-contribution (default-to { contribution-amount: u0, tokens-allocated: u0, claimed: false } 
                           (map-get? contributor-rewards { campaign-id: campaign-id, contributor: contributor })))
    (reward-amount (calculate-reward campaign-id amount))
  )
    ;; Verify campaign is active
    (asserts! (get is-active campaign-data) (err ERR-CAMPAIGN-INACTIVE))
    (asserts! (<= (get start-block campaign-data) current-block) (err ERR-CAMPAIGN-INACTIVE))
    (asserts! (>= (get end-block campaign-data) current-block) (err ERR-CAMPAIGN-INACTIVE))
    
    ;; Update campaign raised amount
    (map-set campaigns
      { campaign-id: campaign-id }
      (merge campaign-data { raised-amount: (+ (get raised-amount campaign-data) amount) })
    )
    
    ;; Update contributor rewards
    (map-set contributor-rewards
      { campaign-id: campaign-id, contributor: contributor }
      {
        contribution-amount: (+ (get contribution-amount existing-contribution) amount),
        tokens-allocated: (+ (get tokens-allocated existing-contribution) reward-amount),
        claimed: false
      }
    )
    
    (ok true)
  )
)

;; Finalize a campaign and determine if it was successful
(define-public (finalize-campaign (campaign-id uint))
  (let (
    (campaign-data (unwrap! (get-campaign campaign-id) (err ERR-CAMPAIGN-NOT-FOUND)))
    (current-block block-height)
  )
    ;; Verify sender is campaign creator
    (try! (is-campaign-creator campaign-id))
    
    ;; Verify campaign is active and ended
    (asserts! (get is-active campaign-data) (err ERR-CAMPAIGN-INACTIVE))
    (asserts! (> current-block (get end-block campaign-data)) (err ERR-CAMPAIGN-STILL-ACTIVE))
    
    ;; Determine if campaign was successful
    (let (
      (is-successful (>= (get raised-amount campaign-data) (get goal-amount campaign-data)))
    )
      ;; Update campaign status
      (map-set campaigns
        { campaign-id: campaign-id }
        (merge campaign-data 
          { 
            is-active: false,
            is-successful: is-successful
          }
        )
      )
      
      (ok is-successful)
    )
  )
)

;; Claim token rewards for a successful campaign
(define-public (claim-rewards (campaign-id uint))
  (let (
    (campaign-data (unwrap! (get-campaign campaign-id) (err ERR-CAMPAIGN-NOT-FOUND)))
    (contributor-data (unwrap! (map-get? contributor-rewards 
                                { campaign-id: campaign-id, contributor: tx-sender }) 
                              (err ERR-INSUFFICIENT-CONTRIBUTION)))
  )
    ;; Verify campaign is finalized and successful
    (asserts! (not (get is-active campaign-data)) (err ERR-CAMPAIGN-STILL-ACTIVE))
    (asserts! (get is-successful campaign-data) (err ERR-CAMPAIGN-FAILED))
    
    ;; Verify contributor has not already claimed
    (asserts! (not (get claimed contributor-data)) (err ERR-ALREADY-CLAIMED))
    
    ;; Verify contributor is eligible for rewards
    (asserts! (> (get tokens-allocated contributor-data) u0) (err ERR-INSUFFICIENT-CONTRIBUTION))
    
    ;; Transfer tokens to contributor
    (let (
      (token-contract (get token-contract campaign-data))
      (tokens-to-send (get tokens-allocated contributor-data))
    )
      ;; Update claim status before transfer to prevent reentrancy
      (map-set contributor-rewards
        { campaign-id: campaign-id, contributor: tx-sender }
        (merge contributor-data { claimed: true })
      )
      
      ;; Execute transfer from contract to contributor
      (asserts! 
        (is-ok (as-contract (contract-call? token-contract transfer 
                              tokens-to-send 
                              tx-sender 
                              tx-sender 
                              none))) 
        (err ERR-TOKEN-TRANSFER-FAILED)
      )
      
      (ok tokens-to-send)
    )
  )
)

;; Return tokens to campaign creator if campaign failed
(define-public (refund-tokens (campaign-id uint))
  (let (
    (campaign-data (unwrap! (get-campaign campaign-id) (err ERR-CAMPAIGN-NOT-FOUND)))
  )
    ;; Verify sender is campaign creator
    (try! (is-campaign-creator campaign-id))
    
    ;; Verify campaign is finalized and failed
    (asserts! (not (get is-active campaign-data)) (err ERR-CAMPAIGN-STILL-ACTIVE))
    (asserts! (not (get is-successful campaign-data)) (err ERR-CAMPAIGN-FAILED))
    
    ;; Transfer all tokens back to campaign creator
    (let (
      (token-contract (get token-contract campaign-data))
      (tokens-to-refund (get total-tokens-allocated campaign-data))
      (creator (get creator campaign-data))
    )
      ;; Execute transfer from contract to creator
      (asserts! 
        (is-ok (as-contract (contract-call? token-contract transfer 
                              tokens-to-refund 
                              tx-sender 
                              creator 
                              none))) 
        (err ERR-TOKEN-TRANSFER-FAILED)
      )
      
      (ok tokens-to-refund)
    )
  )
)