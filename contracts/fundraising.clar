;; Decentralized Fundraising Contract

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-already-initialized (err u101))
(define-constant err-not-initialized (err u102))
(define-constant err-goal-not-reached (err u103))
(define-constant err-fundraising-ended (err u104))
(define-constant err-invalid-tier (err u105))

;; Data Variables
(define-data-var fundraising-goal uint u0)
(define-data-var fundraising-end-block uint u0)
(define-data-var total-raised uint u0)
(define-data-var is-initialized bool false)

;; Maps
(define-map contributors principal uint)
(define-map tiers uint uint)

;; Public Functions
(define-public (initialize (goal uint) (duration uint))
  (if (var-get is-initialized)
    err-already-initialized
    (begin
      (var-set fundraising-goal goal)
      (var-set fundraising-end-block (+ block-height duration))
      (var-set is-initialized true)
      (ok true))))

(define-public (contribute (amount uint))
  (let ((current-contribution (default-to u0 (map-get? contributors tx-sender))))
    (if (and (var-get is-initialized) (<= block-height (var-get fundraising-end-block)))
      (begin
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (map-set contributors tx-sender (+ current-contribution amount))
        (var-set total-raised (+ (var-get total-raised) amount))
        (ok true))
      err-fundraising-ended)))

(define-public (claim-funds)
  (if (and (is-eq tx-sender contract-owner) 
           (>= (var-get total-raised) (var-get fundraising-goal)))
    (as-contract (stx-transfer? (var-get total-raised) tx-sender contract-owner))
    err-goal-not-reached))

(define-public (refund)
  (let ((contribution (default-to u0 (map-get? contributors tx-sender))))
    (if (and (< (var-get total-raised) (var-get fundraising-goal))
             (> block-height (var-get fundraising-end-block)))
      (begin
        (try! (as-contract (stx-transfer? contribution tx-sender tx-sender)))
        (map-delete contributors tx-sender)
        (var-set total-raised (- (var-get total-raised) contribution))
        (ok true))
      err-goal-not-reached)))

(define-public (set-tier (tier-id uint) (amount uint))
  (if (is-eq tx-sender contract-owner)
    (begin
      (map-set tiers tier-id amount)
      (ok true))
    err-owner-only))

;; Read-only Functions
(define-read-only (get-goal)
  (ok (var-get fundraising-goal)))

(define-read-only (get-end-block)
  (ok (var-get fundraising-end-block)))

(define-read-only (get-total-raised)
  (ok (var-get total-raised)))

(define-read-only (get-contribution (contributor principal))
  (ok (default-to u0 (map-get? contributors contributor))))

(define-read-only (get-tier-amount (tier-id uint))
  (ok (default-to u0 (map-get? tiers tier-id))))

(define-read-only (is-goal-reached)
  (ok (>= (var-get total-raised) (var-get fundraising-goal))))

