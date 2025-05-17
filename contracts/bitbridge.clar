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