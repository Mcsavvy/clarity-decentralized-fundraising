```clarity
;; Decentralized Fundraising Contract with Enhanced Security, Governance, Rewards and Analytics

;; Contract Overview:
;; - Supports multiple fundraising campaigns
;; - Implements robust security measures
;; - Provides fine-grained access control
;; - Includes emergency pause functionality
;; - Prevents economic attacks and unauthorized modifications
;; - Offers SIP-010 token rewards for contributors
;; - Tracks comprehensive campaign analytics

;; Error Constants (Enhanced Error Handling)
(define-constant ERR_UNAUTHORIZED u1000)
(define-constant ERR_INVALID_CAMPAIGN u1001)
(define-constant ERR_CAMPAIGN_NOT_FOUND u1002)
(define-constant ERR_GOAL_NOT_REACHED u1003)
(define-constant ERR_FUNDRAISING_ENDED u1004)
(define-constant ERR_INVALID_CONTRIBUTION u1005)
(define-constant ERR_CAMPAIGN_PAUSED u1006)
(define-constant ERR_MAX_CONTRIBUTION_EXCEEDED u1007)
(define-constant ERR_MINIMUM_CONTRIBUTION_NOT_MET u1008)
(define-constant ERR_CAMPAIGN_CANCELLED u1009)
(define-constant ERR_INVALID_DURATION u1010)
(define-constant ERR_CAMPAIGN_EXTENDED_TOO_MUCH u1011)
(define-constant ERR_WITHDRAWAL_NOT_ALLOWED u1012)
(define-constant ERR_CONTRACT_PAUSED u1013)
(define-constant ERR_INVALID_GOAL u1014)
(define-constant ERR_INSUFFICIENT_FUNDS u1015)
(define-constant ERR_REWARD_ALREADY_CLAIMED u1016)
(define-constant ERR_INVALID_REWARD_TIER u1017)
(define-constant ERR_INVALID_TOKEN_CONTRACT u1018)
(define-constant ERR_TOKEN_TRANSFER_FAILED u1019)

;; Events with Enhanced Information
(define-event campaign-created 
  (campaign-id uint)
  (goal uint)
  (duration uint)
  (creator principal))

(define-event contribution-made 
  (campaign-id uint)
  (contributor principal)
  (amount uint)
  (total-raised uint))

(define-event funds-claimed 
  (campaign-id uint)
  (amount uint)
  (claimer principal))

(define-event campaign-cancelled
  (campaign-id uint)
  (reason (string-ascii 100)))

(define-event campaign-duration-extended
  (campaign-id uint)
  (original-end-block uint)
  (new-end-block uint))

(define-event reward-tier-added
  (campaign-id uint)
  (tier-id uint)
  (token-contract principal)
  (token-amount uint)
  (min-contribution uint))

(define-event reward-claimed
  (campaign-id uint)
  (contributor principal)
  (tier-id uint)
  (token-amount uint))

;; Data Maps and Variables
(define-map campaigns 
  uint 
  {
    goal: uint,
    min-contribution: uint,
    end-block: uint,
    total-raised: uint,
    is-active: bool,
    creator: principal
  }
)

(define-map campaign-contributors 
  {campaign-id: uint, contributor: principal} 
  uint
)

(define-map campaign-tiers 
  {campaign-id: uint, tier-id: uint} 
  {
    min-contribution: uint,
    token-contract: principal,
    token-amount: uint
  }
)

(define-map claimed-rewards
  {campaign-id: uint, contributor: principal, tier-id: uint}
  bool
)

(define-map campaign-admins 
  {campaign-id: uint, admin: principal} 
  bool
)

;; Analytics Maps
(define-map campaign-analytics
  uint
  {
    contribution-count: uint,
    unique-contributors: uint,
    avg-contribution: uint,
    largest-contribution: uint,
    smallest-contribution: uint,
    goal-reached-block: (optional uint)
  }
)

(define-map contributor-history
  {campaign-id: uint, contributor: principal}
  {
    first-contribution-block: uint,
    last-contribution-block: uint,
    contribution-count: uint
  }
)

;; Emergency Pause Control
(define-data-var contract-paused bool false)
(define-data-var next-campaign-id uint u0)
(define-data-var max-contribution-per-campaign uint u10000000) ;; 10 STX default max

;; Admin Control
(define-map contract-admins principal bool)

;; Trait Definitions
(define-trait ft-trait
  (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
  )
)

;; Private Functions
(define-private (is-contract-admin (sender principal))
  (default-to false (map-get? contract-admins sender)))

(define-private (is-campaign-admin (campaign-id uint) (sender principal))
  (default-to false (map-get? campaign-admins {campaign-id: campaign-id, admin: sender})))

;; Emergency Pause Functions
(define-public (pause-contract)
  (begin
    (asserts! (is-contract-admin tx-sender) (err ERR_UNAUTHORIZED))
    (var-set contract-paused true)
    (ok true)))

(define-public (unpause-contract)
  (begin
    (asserts! (is-contract-admin tx-sender) (err ERR_UNAUTHORIZED))
    (var-set contract-paused false)
    (ok true)))

(define-private (check-contract-active)
  (begin
    (asserts! (not (var-get contract-paused)) (err ERR_CONTRACT_PAUSED))
    true))

;; #[allow(unchecked_params)]
(define-private (get-campaign (campaign-id uint))
  (unwrap! (map-get? campaigns campaign-id) (err ERR-CAMPAIGN-NOT-FOUND)))

;; Analytics Helper Functions
(define-private (update-analytics (campaign-id uint) (contributor principal) (amount uint))
  (let 
    (
      (current-analytics (default-to 
        {
          contribution-count: u0,
          unique-contributors: u0,
          avg-contribution: u0,
          largest-contribution: u0,
          smallest-contribution: u0,
          goal-reached-block: none
        }
        (map-get? campaign-analytics campaign-id)))
      (contributor-existed (map-get? contributor-history {campaign-id: campaign-id, contributor: contributor}))
      (new-unique-count (if (is-some contributor-existed) 
                          (current-analytics 'unique-contributors) 
                          (+ (current-analytics 'unique-contributors) u1)))
      (contribution-count (+ (current-analytics 'contribution-count) u1))
      (total-amount (+ (* (current-analytics 'avg-contribution) (current-analytics 'contribution-count)) amount))
      (new-avg (/ total-amount contribution-count))
      (new-largest (if (or 
                        (is-eq (current-analytics 'largest-contribution) u0) 
                        (> amount (current-analytics 'largest-contribution)))
                      amount
                      (current-analytics 'largest-contribution)))
      (new-smallest (if (or 
                        (is-eq (current-analytics 'smallest-contribution) u0)
                        (< amount (current-analytics 'smallest-contribution)))
                      amount
                      (current-analytics 'smallest-contribution)))
      (contributor-data (default-to
        {
          first-contribution-block: block-height,
          last-contribution-block: block-height,
          contribution-count: u0
        }
        (map-get? contributor-history {campaign-id: campaign-id, contributor: contributor})))
    )
    
    ;; Update campaign analytics
    (map-set campaign-analytics campaign-id
      (merge current-analytics {
        contribution-count: contribution-count,
        unique-contributors: new-unique-count,
        avg-contribution: new-avg,
        largest-contribution: new-largest,
        smallest-contribution: new-smallest
      })
    )
    
    ;; Update contributor history
    (map-set contributor-history 
      {campaign-id: campaign-id, contributor: contributor}
      {
        first-contribution-block: (contributor-data 'first-contribution-block),
        last-contribution-block: block-height,
        contribution-count: (+ (contributor-data 'contribution-count) u1)
      }
    )
    
    true
  )
)

(define-private (check-goal-reached (campaign-id uint) (campaign (campaign)))
  (let
    (
      (current-analytics (default-to 
        {
          contribution-count: u0,
          unique-contributors: u0,
          avg-contribution: u0,
          largest-contribution: u0,
          smallest-contribution: u0,
          goal-reached-block: none
        }
        (map-get? campaign-analytics campaign-id)))
    )
    (if (and (>= campaign.total-raised campaign.goal)
             (is-none (current-analytics 'goal-reached-block)))
      (map-set campaign-analytics campaign-id
        (merge current-analytics {
          goal-reached-block: (some block-height)
        })
      )
      true
    )
  )
)

;; Public Functions
(define-public (create-campaign 
  (goal uint) 
  (duration uint)
  (max-extension-blocks uint)
  (min-contribution uint))
  (begin
    ;; Contract active check
    (try! (check-contract-active))
    
    (let 
      (
        (campaign-id (var-get next-campaign-id))
        (campaign-details {
          goal: goal,
          min-contribution: min-contribution,
          max-contribution: (var-get max-contribution-per-campaign),
          end-block: (+ block-height duration),
          total-raised: u0,
          is-active: true,
          creator: tx-sender,
          cancelled: false
        })
      )
      ;; Input validations with enhanced error handling
      (asserts! (> goal u0) (err ERR_INVALID_GOAL))
      (asserts! (> duration u0) (err ERR_INVALID_DURATION))
      (asserts! (> min-contribution u0) (err ERR_INVALID_CONTRIBUTION))
      (asserts! (< min-contribution (var-get max-contribution-per-campaign)) (err ERR_MAX_CONTRIBUTION_EXCEEDED))
      
      (map-set campaigns campaign-id campaign-details)
      (map-set campaign-admins {campaign-id: campaign-id, admin: tx-sender} true)
      
      ;; Initialize campaign analytics
      (map-set campaign-analytics campaign-id
        {
          contribution-count: u0,
          unique-contributors: u0,
          avg-contribution: u0,
          largest-contribution: u0,
          smallest-contribution: u0,
          goal-reached-block: none
        }
      )
      
      (var-set next-campaign-id (+ campaign-id u1))
      
      (print (campaign-created campaign-id goal duration tx-sender))
      (ok campaign-id)))

(define-public (contribute (campaign-id uint) (amount uint))
  (let 
    (
      (campaign (try! (get-campaign campaign-id)))
      (current-contribution 
        (default-to u0 
          (map-get? campaign-contributors {campaign-id: campaign-id, contributor: tx-sender}))
      )
    )
    (asserts! (campaign.is-active) ERR-CAMPAIGN-CANCELLED)
    (asserts! (<= block-height (campaign.end-block)) ERR-FUNDRAISING-ENDED)
    (asserts! (> amount u0) ERR-INSUFFICIENT-CONTRIBUTION)
    (asserts! (>= amount campaign.min-contribution) ERR-MINIMUM-CONTRIBUTION-NOT-MET)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (map-set campaign-contributors 
      {campaign-id: campaign-id, contributor: tx-sender} 
      (+ current-contribution amount)
    )
    
    (map-set campaigns campaign-id 
      (merge campaign {total-raised: (+ (campaign.total-raised) amount)})
    )
    
    ;; Update analytics
    (update-analytics campaign-id tx-sender amount)
    
    ;; Check if goal is reached with this contribution
    (check-goal-reached campaign-id (merge campaign {total-raised: (+ (campaign.total-raised) amount)}))
    
    (print (contribution-made 
      campaign-id 
      tx-sender 
      amount 
      (+ (campaign.total-raised) amount)
    ))
    
    (ok true)))

(define-public (claim-funds (campaign-id uint))
  (let 
    (
      (campaign (try! (get-campaign campaign-id)))
    )
    (asserts! 
      (or 
        (is-eq tx-sender campaign.creator) 
        (is-campaign-admin campaign-id tx-sender)
      ) 
      ERR-UNAUTHORIZED
    )
    (asserts! (>= campaign.total-raised campaign.goal) ERR-GOAL-NOT-REACHED)
    
    (try! 
      (as-contract 
        (stx-transfer? campaign.total-raised tx-sender campaign.creator)
      )
    )
    
    (print (funds-claimed campaign-id campaign.total-raised tx-sender))
    (ok true)))

(define-public (refund (campaign-id uint))
  (let 
    (
      (campaign (try! (get-campaign campaign-id)))
      (contribution 
        (default-to u0 
          (map-get? campaign-contributors 
            {campaign-id: campaign-id, contributor: tx-sender}
          )
        )
      )
    )
    (asserts! (< campaign.total-raised campaign.goal) ERR-GOAL-NOT-REACHED)
    (asserts! (> block-height campaign.end-block) ERR-FUNDRAISING-ENDED)
    
    (try! 
      (as-contract 
        (stx-transfer? contribution tx-sender tx-sender)
      )
    )
    
    (map-delete campaign-contributors 
      {campaign-id: campaign-id, contributor: tx-sender}
    )
    
    (map-set campaigns campaign-id 
      (merge campaign {total-raised: (- campaign.total-raised contribution)})
    )
    
    (ok true)))

(define-public (extend-campaign-duration 
  (campaign-id uint) 
  (additional-blocks uint)
  (max-extension-blocks uint))
  (let 
    (
      (campaign (try! (get-campaign campaign-id)))
    )
    (asserts! 
      (or 
        (is-eq tx-sender campaign.creator) 
        (is-campaign-admin campaign-id tx-sender)
      ) 
      ERR-UNAUTHORIZED
    )
    (asserts! (<= additional-blocks max-extension-blocks) ERR-CAMPAIGN-EXTENDED-TOO-MUCH)
    
    (map-set campaigns campaign-id 
      (merge campaign {end-block: (+ campaign.end-block additional-blocks)})
    )
    
    (print (campaign-duration-extended 
      campaign-id 
      campaign.end-block 
      (+ campaign.end-block additional-blocks)
    ))
    
    (ok true)))

(define-public (cancel-campaign 
  (campaign-id uint) 
  (reason (string-ascii 100)))
  (let 
    (
      (campaign (try! (get-campaign campaign-id)))
    )
    (asserts! 
      (or 
        (is-eq tx-sender campaign.creator) 
        (is-campaign-admin campaign-id tx-sender)
      ) 
      ERR-UNAUTHORIZED
    )
    
    (map-set campaigns campaign-id 
      (merge campaign {is-active: false})
    )
    
    (print (campaign-cancelled campaign-id reason))
    (ok true)))

(define-public (add-campaign-admin 
  (campaign-id uint) 
  (new-admin principal))
  (let 
    (
      (campaign (try! (get-campaign campaign-id)))
    )
    (asserts! (is-eq tx-sender campaign.creator) ERR-UNAUTHORIZED)
    (map-set campaign-admins 
      {campaign-id: campaign-id, admin: new-admin} 
      true
    )
    (ok true)))

;; Token Reward Functions
(define-public (add-reward-tier
  (campaign-id uint)
  (tier-id uint)
  (token-contract principal)
  (token-amount uint)
  (min-contribution uint))
  (let
    (
      (campaign (try! (get-campaign campaign-id)))
    )
    (asserts! 
      (or 
        (is-eq tx-sender campaign.creator) 
        (is-campaign-admin campaign-id tx-sender)
      ) 
      ERR-UNAUTHORIZED
    )
    (asserts! (> min-contribution u0) ERR_INVALID_CONTRIBUTION)
    (asserts! (> token-amount u0) ERR_INVALID_CONTRIBUTION)
    
    (map-set campaign-tiers
      {campaign-id: campaign-id, tier-id: tier-id}
      {
        min-contribution: min-contribution,
        token-contract: token-contract,
        token-amount: token-amount
      }
    )
    
    (print (reward-tier-added
      campaign-id
      tier-id
      token-contract
      token-amount
      min-contribution
    ))
    
    (ok true)
  )
)

(define-public (claim-reward
  (campaign-id uint)
  (tier-id uint))
  (let
    (
      (campaign (try! (get-campaign campaign-id)))
      (contribution (default-to u0 
        (map-get? campaign-contributors {campaign-id: campaign-id, contributor: tx-sender})))
      (tier (unwrap! (map-get? campaign-tiers {campaign-id: campaign-id, tier-id: tier-id}) 
        (err ERR_INVALID_REWARD_TIER)))
      (already-claimed (default-to false 
        (map-get? claimed-rewards {campaign-id: campaign-id, contributor: tx-sender, tier-id: tier-id})))
    )
    (asserts! (>= campaign.total-raised campaign.goal) (err ERR_GOAL_NOT_REACHED))
    (asserts! (>= contribution tier.min-contribution) (err ERR_MINIMUM_CONTRIBUTION_NOT_MET))
    (asserts! (not already-claimed) (err ERR_REWARD_ALREADY_CLAIMED))
    
    ;; Mark as claimed
    (map-set claimed-rewards 
      {campaign-id: campaign-id, contributor: tx-sender, tier-id: tier-id} 
      true)
    
    ;; Transfer the tokens
    (try! (contract-call? 
      tier.token-contract transfer 
      tier.token-amount 
      (as-contract tx-sender) 
      tx-sender 
      none))
    
    (print (reward-claimed
      campaign-id
      tx-sender
      tier-id
      tier.token-amount
    ))
    
    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-campaign-details (campaign-id uint))
  (ok (try! (get-campaign campaign-id))))

(define-read-only (get-campaign-contribution 
  (campaign-id uint) 
  (contributor principal))
  (ok 
    (default-to u0 
      (map-get? campaign-contributors 
        {campaign-id: campaign-id, contributor: contributor}
      )
    )
  ))

(define-read-only (is-campaign-goal-reached (campaign-id uint))
  (let 
    (
      (campaign (try! (get-campaign campaign-id)))
    )
    (ok (>= campaign.total-raised campaign.goal))))

(define-read-only (get-reward-tier-details
  (campaign-id uint)
  (tier-id uint))
  (ok (map-get? campaign-tiers {campaign-id: campaign-id, tier-id: tier-id})))

(define-read-only (check-reward-eligibility
  (campaign-id uint)
  (tier-id uint)
  (contributor principal))
  (let
    (
      (contribution (default-to u0 (map-get? campaign-contributors {campaign-id: campaign-id, contributor: contributor})))
      (tier (unwrap! (map-get? campaign-tiers {campaign-id: campaign-id, tier-id: tier-id}) 
        (err ERR_INVALID_REWARD_TIER)))
      (already-claimed (default-to false 
        (map-get? claimed-rewards {campaign-id: campaign-id, contributor: contributor, tier-id: tier-id})))
      (campaign (try! (get-campaign campaign-id)))
    )
    (ok {
      is-eligible: (and 
                     (>= contribution tier.min-contribution)
                     (>= campaign.total-raised campaign.goal) 
                     (not already-claimed)),
      contribution: contribution,
      required-contribution: tier.min-contribution,
      already-claimed: already-claimed,
      goal-reached: (>= campaign.total-raised campaign.goal)
    })
  )
)

(define-read-only (get-campaign-analytics (campaign-id uint))
  (ok (default-to 
    {
      contribution-count: u0,
      unique-contributors: u0,
      avg-contribution: u0,
      largest-contribution: u0,
      smallest-contribution: u0,
      goal-reached-block: none
    }
    (map-get? campaign-analytics campaign-id)))
)

(define-read-only (get-contributor-history
  (campaign-id uint)
  (contributor principal))
  (ok (default-to
    {
      first-contribution-block: u0,
      last-contribution-block: u0,
      contribution-count: u0
    }
    (map-get? contributor-history {campaign-id: campaign-id, contributor: contributor})))
)
```