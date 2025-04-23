;; Multi-Campaign Decentralized Fundraising Contract with Advanced Features

;; Error Constants (Extended Error Handling)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-CAMPAIGN-NOT-FOUND (err u101))
(define-constant ERR-CAMPAIGN-ALREADY-EXISTS (err u102))
(define-constant ERR-GOAL-NOT-REACHED (err u103))
(define-constant ERR-FUNDRAISING-ENDED (err u104))
(define-constant ERR-INVALID-TIER (err u105))
(define-constant ERR-INSUFFICIENT-CONTRIBUTION (err u106))
(define-constant ERR-UNAUTHORIZED (err u107))
(define-constant ERR-INVALID-DURATION (err u108))
(define-constant ERR-INVALID-GOAL (err u109))
(define-constant ERR-CAMPAIGN-CANCELLED (err u110))
(define-constant ERR-CAMPAIGN-EXTENDED-TOO-MUCH (err u111))
(define-constant ERR-MINIMUM-CONTRIBUTION-NOT-MET (err u112))

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
  uint
)

(define-map campaign-admins 
  {campaign-id: uint, admin: principal} 
  bool
)

(define-data-var next-campaign-id uint u0)

;; Private Functions
(define-private (is-campaign-admin (campaign-id uint) (sender principal))
  (default-to false (map-get? campaign-admins {campaign-id: campaign-id, admin: sender})))

;; #[allow(unchecked_params)]
(define-private (get-campaign (campaign-id uint))
  (unwrap! (map-get? campaigns campaign-id) (err ERR-CAMPAIGN-NOT-FOUND)))

;; Public Functions
(define-public (create-campaign 
  (goal uint) 
  (duration uint)
  (max-extension-blocks uint)
  (min-contribution uint))
  (let 
    (
      (campaign-id (var-get next-campaign-id))
      (campaign-details {
        goal: goal,
        min-contribution: min-contribution,
        end-block: (+ block-height duration),
        total-raised: u0,
        is-active: true,
        creator: tx-sender
      })
    )
    (asserts! (> goal u0) ERR-INVALID-GOAL)
    (asserts! (> duration u0) ERR-INVALID-DURATION)
    (asserts! (> min-contribution u0) ERR-INSUFFICIENT-CONTRIBUTION)
    
    (map-set campaigns campaign-id campaign-details)
    (map-set campaign-admins {campaign-id: campaign-id, admin: tx-sender} true)
    
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

