;; campaign-analytics
;; 
;; This contract provides comprehensive analytics capabilities for fundraising campaigns
;; on the Stacks blockchain. It tracks and analyzes key performance metrics to help campaign
;; creators optimize their fundraising strategies and provides transparency to contributors.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-CAMPAIGN-NOT-FOUND (err u101))
(define-constant ERR-INVALID-METRIC (err u102))
(define-constant ERR-INVALID-PARAMETER (err u103))
(define-constant ERR-CAMPAIGN-EXISTS (err u104))
(define-constant ERR-NO-DATA (err u105))

;; Data structures

;; Basic campaign information
(define-map campaigns
  { campaign-id: uint }
  {
    creator: principal,
    name: (string-ascii 100),
    description: (string-utf8 500),
    start-block: uint,
    end-block: uint,
    target-amount: uint,
    category: (string-ascii 50)
  }
)

;; Store contribution data for analytics
(define-map contributions
  { campaign-id: uint, contributor: principal, timestamp: uint }
  {
    amount: uint,
    reward-tier: uint,
    referral-source: (optional (string-ascii 50))
  }
)

;; Store aggregated metrics for each campaign
(define-map campaign-metrics
  { campaign-id: uint }
  {
    total-contributions: uint,
    total-contributors: uint,
    average-contribution: uint,
    largest-contribution: uint
  }
)

;; Store daily contribution totals for trend analysis
(define-map daily-metrics
  { campaign-id: uint, day: uint }
  {
    contribution-count: uint,
    contribution-amount: uint
  }
)

;; Store reward tier performance metrics
(define-map tier-performance
  { campaign-id: uint, tier-id: uint }
  {
    contributors-count: uint,
    total-amount: uint,
    conversion-rate: uint  ;; Scaled by 100 (e.g., 1234 = 12.34%)
  }
)

;; Store benchmark data for performance comparison
(define-map category-benchmarks
  { category: (string-ascii 50) }
  {
    avg-success-rate: uint,   ;; Scaled by 100
    avg-contribution: uint,
    avg-duration-blocks: uint,
    avg-contributors: uint
  }
)

;; Counter for unique campaign IDs
(define-data-var next-campaign-id uint u1)

;; Private functions

;; Generate a new unique campaign ID
(define-private (get-next-campaign-id)
  (let ((current-id (var-get next-campaign-id)))
    (var-set next-campaign-id (+ current-id u1))
    current-id
  )
)

;; Calculate the daily ID from a block height
;; Assumes approximately 144 blocks per day (10 min block time)
(define-private (block-to-day (block-height uint))
  (/ block-height u144)
)

;; Update daily contribution metrics
(define-private (update-daily-metrics (campaign-id uint) (amount uint))
  (let (
    (current-block-height block-height)
    (day (block-to-day block-height))
    (existing-metrics (default-to 
                        { contribution-count: u0, contribution-amount: u0 }
                        (map-get? daily-metrics { campaign-id: campaign-id, day: day })))
  )
    (map-set daily-metrics
      { campaign-id: campaign-id, day: day }
      {
        contribution-count: (+ (get contribution-count existing-metrics) u1),
        contribution-amount: (+ (get contribution-amount existing-metrics) amount)
      }
    )
  )
)

;; Update the overall campaign metrics when a new contribution is recorded
(define-private (update-campaign-metrics (campaign-id uint) (amount uint))
  (let (
    (existing-metrics (default-to 
                        { total-contributions: u0, total-contributors: u0, average-contribution: u0, largest-contribution: u0 }
                        (map-get? campaign-metrics { campaign-id: campaign-id })))
    (new-total (+ (get total-contributions existing-metrics) amount))
    (new-count (+ (get total-contributors existing-metrics) u1))
    (new-avg (/ new-total new-count))
    (new-largest (if (> amount (get largest-contribution existing-metrics))
                    amount
                    (get largest-contribution existing-metrics)))
  )
    (map-set campaign-metrics
      { campaign-id: campaign-id }
      {
        total-contributions: new-total,
        total-contributors: new-count,
        average-contribution: new-avg,
        largest-contribution: new-largest
      }
    )
  )
)

;; Update tier performance metrics when a contribution selects a reward tier
(define-private (update-tier-metrics (campaign-id uint) (tier-id uint) (amount uint))
  (let (
    (existing-metrics (default-to 
                        { contributors-count: u0, total-amount: u0, conversion-rate: u0 }
                        (map-get? tier-performance { campaign-id: campaign-id, tier-id: tier-id })))
    (new-count (+ (get contributors-count existing-metrics) u1))
    (new-total (+ (get total-amount existing-metrics) amount))
    ;; We would calculate conversion rate here, but would need additional data on tier views
  )
    (map-set tier-performance
      { campaign-id: campaign-id, tier-id: tier-id }
      {
        contributors-count: new-count,
        total-amount: new-total,
        conversion-rate: (get conversion-rate existing-metrics) ;; Placeholder - would update in real implementation
      }
    )
  )
)

;; Check if a principal is authorized for a campaign
(define-private (is-campaign-creator (campaign-id uint) (caller principal))
  (match (map-get? campaigns { campaign-id: campaign-id })
    campaign (is-eq (get creator campaign) caller)
    false
  )
)

;; Read-only functions

;; Get basic campaign information
(define-read-only (get-campaign-info (campaign-id uint))
  (match (map-get? campaigns { campaign-id: campaign-id })
    campaign (ok campaign)
    (err ERR-CAMPAIGN-NOT-FOUND)
  )
)

;; Get the current campaign metrics
(define-read-only (get-campaign-metrics (campaign-id uint))
  (match (map-get? campaign-metrics { campaign-id: campaign-id })
    metrics (ok metrics)
    (err ERR-NO-DATA)
  )
)

;; Get daily contribution data for trend analysis
(define-read-only (get-daily-metrics (campaign-id uint) (day uint))
  (match (map-get? daily-metrics { campaign-id: campaign-id, day: day })
    metrics (ok metrics)
    (err ERR-NO-DATA)
  )
)

;; Get performance data for a specific reward tier
(define-read-only (get-tier-performance (campaign-id uint) (tier-id uint))
  (match (map-get? tier-performance { campaign-id: campaign-id, tier-id: tier-id })
    metrics (ok metrics)
    (err ERR-NO-DATA)
  )
)

;; Get category benchmark data for comparison
(define-read-only (get-category-benchmarks (category (string-ascii 50)))
  (match (map-get? category-benchmarks { category: category })
    benchmarks (ok benchmarks)
    (err ERR-NO-DATA)
  )
)

;; Calculate the percentage of funding target achieved
(define-read-only (get-funding-progress (campaign-id uint))
  (match (map-get? campaigns { campaign-id: campaign-id })
    campaign (match (map-get? campaign-metrics { campaign-id: campaign-id })
      metrics (ok {
                  percentage: (/ (* (get total-contributions metrics) u10000) (get target-amount campaign)),
                  current-amount: (get total-contributions metrics),
                  target-amount: (get target-amount campaign)
                })
      (err ERR-NO-DATA))
    (err ERR-CAMPAIGN-NOT-FOUND)
  )
)

;; Calculate the time remaining for a campaign (in blocks)
(define-read-only (get-campaign-time-remaining (campaign-id uint))
  (match (map-get? campaigns { campaign-id: campaign-id })
    campaign (let ((end-block (get end-block campaign))
                   (current-block block-height))
              (if (> end-block current-block)
                  (ok (- end-block current-block))
                  (ok u0)))
    (err ERR-CAMPAIGN-NOT-FOUND)
  )
)

;; Public functions

;; Register a new campaign for analytics tracking
(define-public (register-campaign (name (string-ascii 100))
                                 (description (string-utf8 500))
                                 (start-block uint)
                                 (end-block uint)
                                 (target-amount uint)
                                 (category (string-ascii 50)))
  (let ((campaign-id (get-next-campaign-id)))
    (asserts! (>= start-block block-height) (err ERR-INVALID-PARAMETER))
    (asserts! (> end-block start-block) (err ERR-INVALID-PARAMETER))
    (asserts! (> target-amount u0) (err ERR-INVALID-PARAMETER))
    
    (map-set campaigns
      { campaign-id: campaign-id }
      {
        creator: tx-sender,
        name: name,
        description: description,
        start-block: start-block,
        end-block: end-block,
        target-amount: target-amount,
        category: category
      }
    )
    
    ;; Initialize the campaign metrics
    (map-set campaign-metrics
      { campaign-id: campaign-id }
      {
        total-contributions: u0,
        total-contributors: u0,
        average-contribution: u0,
        largest-contribution: u0
      }
    )
    
    (ok campaign-id)
  )
)

;; Record a new contribution for analytics tracking
(define-public (record-contribution (campaign-id uint)
                                   (contributor principal)
                                   (amount uint)
                                   (reward-tier uint)
                                   (referral-source (optional (string-ascii 50))))
  (begin
    ;; Verify the campaign exists
    (asserts! (is-some (map-get? campaigns { campaign-id: campaign-id })) (err ERR-CAMPAIGN-NOT-FOUND))
    
    ;; Only the campaign creator can record contributions
    (asserts! (is-campaign-creator campaign-id tx-sender) (err ERR-NOT-AUTHORIZED))
    
    ;; Store the contribution data
    (map-set contributions
      { campaign-id: campaign-id, contributor: contributor, timestamp: block-height }
      {
        amount: amount,
        reward-tier: reward-tier,
        referral-source: referral-source
      }
    )
    
    ;; Update all the relevant metrics
    (update-campaign-metrics campaign-id amount)
    (update-daily-metrics campaign-id amount)
    (update-tier-metrics campaign-id reward-tier amount)
    
    (ok true)
  )
)

;; Update category benchmark data (typically called by an admin or oracle)
(define-public (update-category-benchmark (category (string-ascii 50))
                                         (avg-success-rate uint)
                                         (avg-contribution uint)
                                         (avg-duration-blocks uint)
                                         (avg-contributors uint))
  (begin
    ;; Add authorization mechanism here in production
    ;; For simplicity, we're not implementing authorization in this example
    
    (map-set category-benchmarks
      { category: category }
      {
        avg-success-rate: avg-success-rate,
        avg-contribution: avg-contribution,
        avg-duration-blocks: avg-duration-blocks,
        avg-contributors: avg-contributors
      }
    )
    
    (ok true)
  )
)