;; Energy Token Contract
;; Tokenized representation of renewable energy units

;; Token constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-source-not-verified (err u104))
(define-constant err-invalid-recipient (err u105))

;; Token properties
(define-fungible-token energy-token)
(define-data-var token-name (string-ascii 32) "RenewableEnergyToken")
(define-data-var token-symbol (string-ascii 10) "RET")
(define-data-var token-uri (optional (string-utf8 256)) none)
(define-data-var token-decimals uint u6)

;; Energy source verification data
(define-map verified-sources principal bool)
(define-map energy-metadata uint { source-type: (string-ascii 20), production-date: uint, location: (string-ascii 50), verified: bool })
(define-data-var next-metadata-id uint u1)

;; Producer registration
(define-map energy-producers principal { registered: bool, total-produced: uint, verification-score: uint })

;; Energy trading data
(define-map energy-orders uint { producer: principal, amount: uint, price-per-unit: uint, energy-type: (string-ascii 20), available: bool })
(define-data-var next-order-id uint u1)

;; Administrative functions
(define-public (set-token-uri (value (optional (string-utf8 256))))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (var-set token-uri value))
  )
)

;; Producer registration and verification
(define-public (register-producer (producer principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set energy-producers producer { registered: true, total-produced: u0, verification-score: u100 }))
  )
)

(define-public (verify-energy-source (source principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set verified-sources source true))
  )
)

;; Energy token minting with metadata
(define-public (mint-energy-tokens (recipient principal) (amount uint) (source-type (string-ascii 20)) (location (string-ascii 50)))
  (let
    (
      (metadata-id (var-get next-metadata-id))
      (is-verified (default-to false (map-get? verified-sources tx-sender)))
      (producer-data (default-to { registered: false, total-produced: u0, verification-score: u0 } (map-get? energy-producers tx-sender)))
    )
    (asserts! (get registered producer-data) err-source-not-verified)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! is-verified err-source-not-verified)
    
    ;; Store energy metadata
    (map-set energy-metadata metadata-id {
      source-type: source-type,
      production-date: block-height,
      location: location,
      verified: true
    })
    
    ;; Update producer statistics
    (map-set energy-producers tx-sender (merge producer-data { total-produced: (+ (get total-produced producer-data) amount) }))
    
    ;; Mint tokens
    (var-set next-metadata-id (+ metadata-id u1))
    (ft-mint? energy-token amount recipient)
  )
)

;; Energy token burning (consumption)
(define-public (burn-energy-tokens (amount uint))
  (begin
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (>= (ft-get-balance energy-token tx-sender) amount) err-insufficient-balance)
    (ft-burn? energy-token amount tx-sender)
  )
)

;; Create energy trading order
(define-public (create-energy-order (amount uint) (price-per-unit uint) (energy-type (string-ascii 20)))
  (let
    (
      (order-id (var-get next-order-id))
      (producer-data (map-get? energy-producers tx-sender))
    )
    (asserts! (is-some producer-data) err-source-not-verified)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (> price-per-unit u0) err-invalid-amount)
    (asserts! (>= (ft-get-balance energy-token tx-sender) amount) err-insufficient-balance)
    
    ;; Create order
    (map-set energy-orders order-id {
      producer: tx-sender,
      amount: amount,
      price-per-unit: price-per-unit,
      energy-type: energy-type,
      available: true
    })
    
    (var-set next-order-id (+ order-id u1))
    (ok order-id)
  )
)

;; Purchase energy from order
(define-public (purchase-energy (order-id uint) (amount uint))
  (let
    (
      (order (unwrap! (map-get? energy-orders order-id) err-invalid-amount))
      (total-cost (* amount (get price-per-unit order)))
    )
    (asserts! (get available order) err-invalid-amount)
    (asserts! (>= (get amount order) amount) err-insufficient-balance)
    (asserts! (> amount u0) err-invalid-amount)
    
    ;; Transfer tokens from producer to buyer
    (try! (ft-transfer? energy-token amount (get producer order) tx-sender))
    
    ;; Update order amount
    (if (is-eq (get amount order) amount)
      ;; Order fully filled, mark as unavailable
      (map-set energy-orders order-id (merge order { amount: u0, available: false }))
      ;; Partial fill, update remaining amount
      (map-set energy-orders order-id (merge order { amount: (- (get amount order) amount) }))
    )
    
    (ok true)
  )
)

;; SIP-010 required functions
(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    (asserts! (or (is-eq tx-sender sender) (is-eq contract-caller sender)) err-not-token-owner)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (not (is-eq sender recipient)) err-invalid-recipient)
    (ft-transfer? energy-token amount sender recipient)
  )
)

(define-read-only (get-name)
  (ok (var-get token-name))
)

(define-read-only (get-symbol)
  (ok (var-get token-symbol))
)

(define-read-only (get-decimals)
  (ok (var-get token-decimals))
)

(define-read-only (get-balance (who principal))
  (ok (ft-get-balance energy-token who))
)

(define-read-only (get-total-supply)
  (ok (ft-get-supply energy-token))
)

(define-read-only (get-token-uri)
  (ok (var-get token-uri))
)

;; Read-only functions for energy data
(define-read-only (get-energy-metadata (metadata-id uint))
  (map-get? energy-metadata metadata-id)
)

(define-read-only (get-producer-info (producer principal))
  (map-get? energy-producers producer)
)

(define-read-only (get-energy-order (order-id uint))
  (map-get? energy-orders order-id)
)

(define-read-only (is-verified-source (source principal))
  (default-to false (map-get? verified-sources source))
)

;; Initialize contract
(begin
  (map-set verified-sources contract-owner true)
  (map-set energy-producers contract-owner { registered: true, total-produced: u0, verification-score: u100 })
)


;; title: energy-token
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

