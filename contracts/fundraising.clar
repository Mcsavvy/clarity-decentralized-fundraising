;; Decentralized Fundraising Contract with Enhanced Security and Logging

;; Constants
(define-constant contract-owner tx-sender)
(define-constant deployer-principal contract-caller)

;; Error Codes
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-ALREADY-INITIALIZED (err u101))
(define-constant ERR-NOT-INITIALIZED (err u102))
(define-constant ERR-GOAL-NOT-REACHED (err u103))
(define-constant ERR-FUNDRAISING-ENDED (err u104))
(define-constant ERR-INVALID-TIER (err u105))
(define-constant ERR-INSUFFICIENT-CONTRIBUTION (err u106))
(define-constant ERR-UNAUTHORIZED (err u107))
(define-constant ERR-INVALID-DURATION (err u108))
(define-constant ERR-INVALID-GOAL (err u109))

;; Events
(define-event fundraising-initialized 
  (goal uint)
  (duration uint)
  (initialized-by principal))

(define-event contribution-made 
  (contributor principal)
  (amount uint)
  (total-raised uint))

(define-event tier-set 
  (tier-id uint)
  (amount uint))

(define-event funds-claimed 
  (amount uint)
  (claimer principal))

(define-event refund-processed 
  (contributor principal)
  (amount uint))

;; Data Variables
(define-data-var fundraising-goal uint u0)
(define-data-var fundraising-end-block uint u0)
(define-data-var total-raised uint u0)
(define-data-var is-initialized bool false)
(define-data-var admin principal tx-sender)

;; Maps
(define-map contributors principal uint)
(define-map tiers uint uint)
(define-map admin-list principal bool)

;; Private Functions
(define-private (is-admin (sender principal))
  (default-to false (map-get? admin-list sender)))

;; Public Functions
(define-public (initialize (goal uint) (duration uint))
  (begin
    (asserts! (not (var-get is-initialized)) ERR-ALREADY-INITIALIZED)
    (asserts! (> goal u0) ERR-INVALID-GOAL)
    (asserts! (> duration u0) ERR-INVALID-DURATION)
    (var-set fundraising-goal goal)
    (var-set fundraising-end-block (+ block-height duration))
    (var-set is-initialized true)
    (print (fundraising-initialized goal duration tx-sender))
    (ok true)))

(define-public (contribute (amount uint))
  (let ((current-contribution (default-to u0 (map-get? contributors tx-sender))))
    (asserts! (var-get is-initialized) ERR-NOT-INITIALIZED)
    (asserts! (<= block-height (var-get fundraising-end-block)) ERR-FUNDRAISING-ENDED)
    (asserts! (> amount u0) ERR-INSUFFICIENT-CONTRIBUTION)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set contributors tx-sender (+ current-contribution amount))
    (var-set total-raised (+ (var-get total-raised) amount))
    
    (print (contribution-made tx-sender amount (var-get total-raised)))
    (ok true)))

(define-public (claim-funds)
  (begin
    (asserts! (or (is-eq tx-sender (var-get admin)) (is-admin tx-sender)) ERR-UNAUTHORIZED)
    (asserts! (>= (var-get total-raised) (var-get fundraising-goal)) ERR-GOAL-NOT-REACHED)
    
    (let ((total-amount (var-get total-raised)))
      (try! (as-contract (stx-transfer? total-amount tx-sender contract-owner)))
      (print (funds-claimed total-amount tx-sender))
      (ok true))))

(define-public (refund)
  (let ((contribution (default-to u0 (map-get? contributors tx-sender))))
    (asserts! (< (var-get total-raised) (var-get fundraising-goal)) ERR-GOAL-NOT-REACHED)
    (asserts! (> block-height (var-get fundraising-end-block)) ERR-FUNDRAISING-ENDED)
    
    (try! (as-contract (stx-transfer? contribution tx-sender tx-sender)))
    (map-delete contributors tx-sender)
    (var-set total-raised (- (var-get total-raised) contribution))
    
    (print (refund-processed tx-sender contribution))
    (ok true)))

(define-public (set-tier (tier-id uint) (amount uint))
  (begin
    (asserts! (or (is-eq tx-sender (var-get admin)) (is-admin tx-sender)) ERR-UNAUTHORIZED)
    (map-set tiers tier-id amount)
    (print (tier-set tier-id amount))
    (ok true)))

(define-public (add-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR-OWNER-ONLY)
    (map-set admin-list new-admin true)
    (ok true)))

(define-public (remove-admin (admin-to-remove principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR-OWNER-ONLY)
    (map-delete admin-list admin-to-remove)
    (ok true)))

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

(define-read-only (get-admin)
  (ok (var-get admin)))

