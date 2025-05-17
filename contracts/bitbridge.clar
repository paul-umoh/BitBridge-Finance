;; BitBridge Finance: Bitcoin-Backed Lending Protocol
;;
;; BitBridge Finance is a decentralized lending protocol enabling 
;; Bitcoin holders to unlock liquidity without selling their BTC.
;; Users deposit Bitcoin as collateral, borrow stablecoins, and can
;; repay with interest to reclaim their full collateral.
;;
;; Key features:
;;  - Secure Bitcoin collateralization
;;  - Algorithmic interest rates
;;  - Configurable risk parameters
;;  - Transparent liquidation mechanics
;;  - Protocol governance


;; Constants and Error Codes

;; Security and Access Errors
(define-constant ERR_UNAUTHORIZED (err u1000))
(define-constant ERR_PROTOCOL_PAUSED (err u1012))

;; Vault Operation Errors
(define-constant ERR_VAULT_ALREADY_EXISTS (err u1004))
(define-constant ERR_VAULT_NOT_FOUND (err u1005))
(define-constant ERR_VAULT_NOT_UNDERCOLLATERALIZED (err u1010))

;; Financial Constraint Errors
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u1001))
(define-constant ERR_BORROW_LIMIT_EXCEEDED (err u1002))
(define-constant ERR_INSUFFICIENT_LIQUIDITY (err u1003))
(define-constant ERR_INSUFFICIENT_DEPOSIT (err u1006))
(define-constant ERR_INSUFFICIENT_REPAYMENT (err u1007))
(define-constant ERR_MINIMUM_COLLATERAL_RATIO (err u1009))

;; Technical Errors
(define-constant ERR_INVALID_AMOUNT (err u1008))
(define-constant ERR_ORACLE_ERROR (err u1011))

;; Protocol Configuration Parameters

;; Risk Parameters
(define-data-var minimum-collateral-ratio uint u150) ;; 150% - Required for borrowing
(define-data-var liquidation-threshold uint u125) ;; 125% - Threshold for liquidation
(define-data-var liquidation-penalty uint u10) ;; 10% - Penalty for liquidated positions

;; Economic Parameters
(define-data-var borrow-interest-rate uint u5) ;; 5% annualized interest rate
(define-data-var protocol-fee-rate uint u1) ;; 1% of interest as protocol fee

;; Operational Parameters
(define-data-var oracle-price-validity-period uint u3600) ;; Price valid for 1 hour (in blocks)
(define-data-var protocol-paused bool false) ;; Emergency protocol pause switch

;; State Variables

;; Contract Management
(define-data-var contract-owner principal tx-sender)

;; Oracle Data
(define-data-var btc-price-in-usd uint u0) ;; BTC price scaled by 10^8
(define-data-var btc-price-last-updated uint u0) ;; Block height of last price update

;; Protocol Statistics
(define-data-var total-collateral uint u0) ;; Total BTC collateral in satoshis
(define-data-var total-borrowed uint u0) ;; Total debt in USD cents
(define-data-var total-fees-collected uint u0) ;; Total fees in USD cents

;; Data Maps

;; User Vaults (collateralized debt positions)
(define-map vaults
  { owner: principal }
  {
    collateral-amount: uint, ;; BTC collateral in satoshis
    borrowed-amount: uint, ;; Principal debt in USD cents
    interest-accumulated: uint, ;; Accrued interest in USD cents
    last-interest-update: uint, ;; Block height of last interest calculation
  }
)

;; Protocol Reserve Assets
(define-map protocol-reserves
  { asset: (string-ascii 10) }
  { amount: uint }
)

;; Governance Token Balances
(define-map governance-token-balances
  { owner: principal }
  { balance: uint }
)

;; Authorization and Security Functions

;; Check if caller is contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

;; Check if caller is authorized oracle provider
(define-private (is-authorized-oracle)
  ;; Production implementation would use a whitelist
  (is-eq tx-sender (var-get contract-owner))
)

;; Check if protocol is active (not paused)
(define-private (assert-not-paused)
  (ok (asserts! (not (var-get protocol-paused)) ERR_PROTOCOL_PAUSED))
)

;; Mathematical Helper Functions

;; Safe multiplication and division
;; a * b / c with overflow protection
(define-private (mul-div
    (a uint)
    (b uint)
    (c uint)
  )
  (begin
    (asserts! (> c u0) ERR_INVALID_AMOUNT)
    (ok (/ (* a b) c))
  )
)

;; Oracle Price Feed Functions

;; Update BTC price from authorized oracle
(define-public (update-btc-price (new-price uint))
  (begin
    (asserts! (is-authorized-oracle) ERR_UNAUTHORIZED)
    (asserts! (> new-price u0) ERR_INVALID_AMOUNT)
    (asserts! (< new-price u10000000000) ERR_INVALID_AMOUNT) ;; $100,000 per BTC ceiling
    (var-set btc-price-in-usd new-price)
    (var-set btc-price-last-updated stacks-block-height)
    (ok new-price)
  )
)

;; Retrieve current BTC price, ensuring it's fresh
(define-private (get-btc-price)
  (let (
      (current-price (var-get btc-price-in-usd))
      (last-updated (var-get btc-price-last-updated))
    )
    (if (or
        (is-eq current-price u0)
        (> (- stacks-block-height last-updated)
          (var-get oracle-price-validity-period)
        )
      )
      ERR_ORACLE_ERROR
      (ok current-price)
    )
  )
)

;; Protocol Administration Functions

;; Transfer contract ownership
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (asserts! (not (is-eq new-owner 'SP000000000000000000002Q6VF78))
      ERR_INVALID_AMOUNT
    )
    (var-set contract-owner new-owner)
    (ok new-owner)
  )
)

;; Update minimum collateral ratio parameter
(define-public (set-minimum-collateral-ratio (new-ratio uint))
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (asserts! (>= new-ratio (var-get liquidation-threshold)) ERR_INVALID_AMOUNT)
    (var-set minimum-collateral-ratio new-ratio)
    (ok new-ratio)
  )
)

;; Update liquidation threshold parameter
(define-public (set-liquidation-threshold (new-threshold uint))
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (asserts! (<= new-threshold (var-get minimum-collateral-ratio))
      ERR_INVALID_AMOUNT
    )
    (var-set liquidation-threshold new-threshold)
    (ok new-threshold)
  )
)

;; Update liquidation penalty parameter
(define-public (set-liquidation-penalty (new-penalty uint))
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (asserts! (<= new-penalty u50) ERR_INVALID_AMOUNT) ;; Maximum 50% penalty
    (var-set liquidation-penalty new-penalty)
    (ok new-penalty)
  )
)

;; Update interest rate parameter
(define-public (set-interest-rate (new-rate uint))
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (asserts! (<= new-rate u50) ERR_INVALID_AMOUNT) ;; Maximum 50% interest rate
    (var-set borrow-interest-rate new-rate)
    (ok new-rate)
  )
)

;; Update protocol fee parameter
(define-public (set-protocol-fee (new-fee uint))
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (asserts! (<= new-fee u50) ERR_INVALID_AMOUNT) ;; Maximum 50% fee
    (var-set protocol-fee-rate new-fee)
    (ok new-fee)
  )
)

;; Emergency pause/unpause protocol
(define-public (toggle-protocol-pause)
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (var-set protocol-paused (not (var-get protocol-paused)))
    (ok (var-get protocol-paused))
  )
)