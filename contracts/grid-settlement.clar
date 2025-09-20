;; Grid Settlement Contract
;; Automated settlement system for energy transactions

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-unauthorized (err u201))
(define-constant err-invalid-amount (err u202))
(define-constant err-insufficient-funds (err u203))
(define-constant err-trade-not-found (err u204))
(define-constant err-trade-already-settled (err u205))
(define-constant err-invalid-price (err u206))
(define-constant err-grid-capacity-exceeded (err u207))
(define-constant err-invalid-participant (err u208))

;; Data variables
(define-data-var grid-operator principal tx-sender)
(define-data-var base-price uint u100) ;; Base price per energy unit in microSTX
(define-data-var price-volatility-factor uint u10) ;; Price adjustment factor (1-100)
(define-data-var total-energy-traded uint u0)
(define-data-var next-trade-id uint u1)
(define-data-var next-settlement-id uint u1)
(define-data-var grid-capacity uint u1000000) ;; Maximum grid capacity
(define-data-var current-grid-load uint u0)

;; Trading data structures
(define-map energy-trades uint {
  seller: principal,
  buyer: principal,
  energy-amount: uint,
  agreed-price: uint,
  trade-timestamp: uint,
  settlement-status: (string-ascii 20),
  energy-type: (string-ascii 20)
})

;; Settlement tracking
(define-map settlements uint {
  trade-id: uint,
  settlement-timestamp: uint,
  final-price: uint,
  grid-fees: uint,
  status: (string-ascii 20)
})

;; Market participant data
(define-map market-participants principal {
  registered: bool,
  total-energy-sold: uint,
  total-energy-bought: uint,
  reputation-score: uint,
  settlement-balance: uint
})

;; Grid stability data
(define-map grid-nodes (string-ascii 20) {
  capacity: uint,
  current-load: uint,
  efficiency-rating: uint,
  maintenance-status: bool
})

;; Price history for market analysis
(define-map price-history uint {
  timestamp: uint,
  price: uint,
  volume: uint,
  market-conditions: (string-ascii 30)
})

(define-data-var price-history-id uint u1)

;; Administrative functions
(define-public (set-grid-operator (new-operator principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (var-set grid-operator new-operator))
  )
)

(define-public (update-base-price (new-price uint))
  (begin
    (asserts! (or (is-eq tx-sender contract-owner) (is-eq tx-sender (var-get grid-operator))) err-unauthorized)
    (asserts! (> new-price u0) err-invalid-price)
    (ok (var-set base-price new-price))
  )
)

(define-public (set-grid-capacity (capacity uint))
  (begin
    (asserts! (or (is-eq tx-sender contract-owner) (is-eq tx-sender (var-get grid-operator))) err-unauthorized)
    (asserts! (> capacity u0) err-invalid-amount)
    (ok (var-set grid-capacity capacity))
  )
)

;; Participant registration
(define-public (register-participant (participant principal))
  (begin
    (asserts! (or (is-eq tx-sender contract-owner) (is-eq tx-sender (var-get grid-operator))) err-unauthorized)
    (ok (map-set market-participants participant {
      registered: true,
      total-energy-sold: u0,
      total-energy-bought: u0,
      reputation-score: u100,
      settlement-balance: u0
    }))
  )
)

;; Dynamic pricing calculation
(define-private (calculate-market-price (energy-amount uint) (energy-type (string-ascii 20)))
  (let
    (
      (base (var-get base-price))
      (volatility (var-get price-volatility-factor))
      (grid-load-factor (/ (* (var-get current-grid-load) u100) (var-get grid-capacity)))
      (demand-adjustment (if (> grid-load-factor u80) (+ base (/ (* base volatility) u100)) base))
    )
    ;; Adjust price based on energy type
    (if (is-eq energy-type "solar")
      (- demand-adjustment (/ demand-adjustment u20)) ;; 5% discount for solar
      (if (is-eq energy-type "wind")
        (- demand-adjustment (/ demand-adjustment u25)) ;; 4% discount for wind
        demand-adjustment ;; Standard price for other types
      )
    )
  )
)

;; Create energy trade
(define-public (create-energy-trade (seller principal) (buyer principal) (energy-amount uint) (energy-type (string-ascii 20)))
  (let
    (
      (trade-id (var-get next-trade-id))
      (market-price (calculate-market-price energy-amount energy-type))
      (seller-data (map-get? market-participants seller))
      (buyer-data (map-get? market-participants buyer))
    )
    (asserts! (is-some seller-data) err-invalid-participant)
    (asserts! (is-some buyer-data) err-invalid-participant)
    (asserts! (get registered (unwrap! seller-data err-invalid-participant)) err-invalid-participant)
    (asserts! (get registered (unwrap! buyer-data err-invalid-participant)) err-invalid-participant)
    (asserts! (> energy-amount u0) err-invalid-amount)
    (asserts! (<= (+ (var-get current-grid-load) energy-amount) (var-get grid-capacity)) err-grid-capacity-exceeded)
    
    ;; Create trade record
    (map-set energy-trades trade-id {
      seller: seller,
      buyer: buyer,
      energy-amount: energy-amount,
      agreed-price: market-price,
      trade-timestamp: block-height,
      settlement-status: "pending",
      energy-type: energy-type
    })
    
    ;; Update grid load
    (var-set current-grid-load (+ (var-get current-grid-load) energy-amount))
    
    ;; Record price history
    (map-set price-history (var-get price-history-id) {
      timestamp: block-height,
      price: market-price,
      volume: energy-amount,
      market-conditions: "normal"
    })
    
    (var-set next-trade-id (+ trade-id u1))
    (var-set price-history-id (+ (var-get price-history-id) u1))
    (ok trade-id)
  )
)

;; Execute trade settlement
(define-public (settle-trade (trade-id uint))
  (let
    (
      (trade (unwrap! (map-get? energy-trades trade-id) err-trade-not-found))
      (settlement-id (var-get next-settlement-id))
      (grid-fee (/ (* (get agreed-price trade) (get energy-amount trade)) u1000)) ;; 0.1% grid fee
      (net-amount (- (* (get agreed-price trade) (get energy-amount trade)) grid-fee))
      (seller-data (unwrap! (map-get? market-participants (get seller trade)) err-invalid-participant))
      (buyer-data (unwrap! (map-get? market-participants (get buyer trade)) err-invalid-participant))
    )
    (asserts! (is-eq (get settlement-status trade) "pending") err-trade-already-settled)
    (asserts! (or (is-eq tx-sender (get seller trade)) (is-eq tx-sender (get buyer trade)) (is-eq tx-sender (var-get grid-operator))) err-unauthorized)
    
    ;; Update trade status
    (map-set energy-trades trade-id (merge trade { settlement-status: "settled" }))
    
    ;; Create settlement record
    (map-set settlements settlement-id {
      trade-id: trade-id,
      settlement-timestamp: block-height,
      final-price: (get agreed-price trade),
      grid-fees: grid-fee,
      status: "completed"
    })
    
    ;; Update participant statistics
    (map-set market-participants (get seller trade) 
      (merge seller-data {
        total-energy-sold: (+ (get total-energy-sold seller-data) (get energy-amount trade)),
        settlement-balance: (+ (get settlement-balance seller-data) net-amount)
      })
    )
    
    (map-set market-participants (get buyer trade)
      (merge buyer-data {
        total-energy-bought: (+ (get total-energy-bought buyer-data) (get energy-amount trade))
      })
    )
    
    ;; Update total energy traded
    (var-set total-energy-traded (+ (var-get total-energy-traded) (get energy-amount trade)))
    (var-set next-settlement-id (+ settlement-id u1))
    
    (ok settlement-id)
  )
)

;; Grid management functions
(define-public (add-grid-node (node-id (string-ascii 20)) (capacity uint) (efficiency uint))
  (begin
    (asserts! (is-eq tx-sender (var-get grid-operator)) err-unauthorized)
    (asserts! (> capacity u0) err-invalid-amount)
    (ok (map-set grid-nodes node-id {
      capacity: capacity,
      current-load: u0,
      efficiency-rating: efficiency,
      maintenance-status: false
    }))
  )
)

(define-public (update-grid-load (node-id (string-ascii 20)) (new-load uint))
  (let
    (
      (node-data (unwrap! (map-get? grid-nodes node-id) err-invalid-amount))
    )
    (asserts! (is-eq tx-sender (var-get grid-operator)) err-unauthorized)
    (asserts! (<= new-load (get capacity node-data)) err-grid-capacity-exceeded)
    (ok (map-set grid-nodes node-id (merge node-data { current-load: new-load })))
  )
)

;; Withdraw settlement balance
(define-public (withdraw-settlement-balance (amount uint))
  (let
    (
      (participant-data (unwrap! (map-get? market-participants tx-sender) err-invalid-participant))
    )
    (asserts! (get registered participant-data) err-unauthorized)
    (asserts! (>= (get settlement-balance participant-data) amount) err-insufficient-funds)
    (asserts! (> amount u0) err-invalid-amount)
    
    ;; Update balance
    (map-set market-participants tx-sender 
      (merge participant-data { settlement-balance: (- (get settlement-balance participant-data) amount) })
    )
    
    ;; Transfer STX (simplified - in real implementation would use stx-transfer?)
    (ok amount)
  )
)

;; Read-only functions
(define-read-only (get-trade-info (trade-id uint))
  (map-get? energy-trades trade-id)
)

(define-read-only (get-settlement-info (settlement-id uint))
  (map-get? settlements settlement-id)
)

(define-read-only (get-participant-info (participant principal))
  (map-get? market-participants participant)
)

(define-read-only (get-current-market-price (energy-amount uint) (energy-type (string-ascii 20)))
  (ok (calculate-market-price energy-amount energy-type))
)

(define-read-only (get-grid-status)
  (ok {
    capacity: (var-get grid-capacity),
    current-load: (var-get current-grid-load),
    utilization: (/ (* (var-get current-grid-load) u100) (var-get grid-capacity)),
    base-price: (var-get base-price)
  })
)

(define-read-only (get-grid-node-info (node-id (string-ascii 20)))
  (map-get? grid-nodes node-id)
)

(define-read-only (get-price-history (history-id uint))
  (map-get? price-history history-id)
)

(define-read-only (get-total-energy-traded)
  (ok (var-get total-energy-traded))
)

;; Initialize contract
(begin
  (map-set market-participants contract-owner {
    registered: true,
    total-energy-sold: u0,
    total-energy-bought: u0,
    reputation-score: u100,
    settlement-balance: u0
  })
)


;; title: grid-settlement
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

