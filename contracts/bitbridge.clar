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

;; Vault Management Functions

;; Deposit BTC collateral
(define-public (deposit-collateral (btc-amount uint))
  (let (
      (user tx-sender)
      (vault-data (map-get? vaults { owner: user }))
    )
    (begin
      (try! (assert-not-paused))
      (asserts! (> btc-amount u0) ERR_INVALID_AMOUNT)
      ;; Create or update vault
      (if (is-some vault-data)
        (let ((existing-vault (unwrap-panic vault-data)))
          (map-set vaults { owner: user } {
            collateral-amount: (+ (get collateral-amount existing-vault) btc-amount),
            borrowed-amount: (get borrowed-amount existing-vault),
            interest-accumulated: (get interest-accumulated existing-vault),
            last-interest-update: (get last-interest-update existing-vault),
          })
        )
        (map-set vaults { owner: user } {
          collateral-amount: btc-amount,
          borrowed-amount: u0,
          interest-accumulated: u0,
          last-interest-update: stacks-block-height,
        })
      )
      ;; Update total collateral
      (var-set total-collateral (+ (var-get total-collateral) btc-amount))
      (ok btc-amount)
    )
  )
)

;; Calculate collateral value in USD cents
(define-private (calculate-collateral-value (btc-amount uint))
  (let ((btc-price (get-btc-price)))
    (if (is-err btc-price)
      btc-price
      (mul-div btc-amount (unwrap-panic btc-price) u100000000) ;; Convert satoshis to BTC and multiply by price
    )
  )
)

;; Calculate maximum borrowable amount based on collateral
(define-private (calculate-max-borrow-amount (collateral-amount uint))
  (let ((collateral-value-result (calculate-collateral-value collateral-amount)))
    (if (is-err collateral-value-result)
      collateral-value-result
      (let ((collateral-value (unwrap-panic collateral-value-result)))
        (mul-div collateral-value u100 (var-get minimum-collateral-ratio))
      )
    )
  )
)

;; Calculate interest for a given period
(define-private (calculate-interest
    (borrowed-amount uint)
    (blocks-passed uint)
  )
  (let ((interest-per-block (/ (var-get borrow-interest-rate) u52560)))
    (unwrap-panic (mul-div borrowed-amount interest-per-block blocks-passed))
  )
)

;; Update accumulated interest for a vault
(define-private (update-interest (vault-data {
  collateral-amount: uint,
  borrowed-amount: uint,
  interest-accumulated: uint,
  last-interest-update: uint,
}))
  (let (
      (blocks-passed (- stacks-block-height (get last-interest-update vault-data)))
      (new-interest (calculate-interest (get borrowed-amount vault-data) blocks-passed))
    )
    {
      collateral-amount: (get collateral-amount vault-data),
      borrowed-amount: (get borrowed-amount vault-data),
      interest-accumulated: (+ (get interest-accumulated vault-data) new-interest),
      last-interest-update: stacks-block-height,
    }
  )
)

;; Check if a vault is undercollateralized
(define-private (is-undercollateralized (vault-data {
  collateral-amount: uint,
  borrowed-amount: uint,
  interest-accumulated: uint,
  last-interest-update: uint,
}))
  (let (
      (collateral-value-result (calculate-collateral-value (get collateral-amount vault-data)))
      (total-debt (+ (get borrowed-amount vault-data) (get interest-accumulated vault-data)))
    )
    (if (is-err collateral-value-result)
      true ;; If oracle error, consider vault at risk
      (let (
          (collateral-value (unwrap-panic collateral-value-result))
          (min-collateral-needed-result (mul-div total-debt (var-get liquidation-threshold) u100))
        )
        (if (is-err min-collateral-needed-result)
          true ;; If calculation error, consider vault at risk
          (< collateral-value (unwrap-panic min-collateral-needed-result))
        )
      )
    )
  )
)

;; Borrowing and Repayment Functions

;; Borrow stablecoins against BTC collateral
(define-public (borrow (amount-to-borrow uint))
  (let (
      (user tx-sender)
      (vault-data-option (map-get? vaults { owner: user }))
    )
    (begin
      (try! (assert-not-paused))
      (asserts! (> amount-to-borrow u0) ERR_INVALID_AMOUNT)
      (asserts! (is-some vault-data-option) ERR_VAULT_NOT_FOUND)
      (let (
          (vault-data (unwrap-panic vault-data-option))
          (updated-vault (update-interest vault-data))
        )
        ;; Check borrowing limit
        (let (
            (max-borrow-result (calculate-max-borrow-amount (get collateral-amount updated-vault)))
            (total-debt (+ (get borrowed-amount updated-vault)
              (get interest-accumulated updated-vault)
            ))
          )
          (if (is-err max-borrow-result)
            max-borrow-result
            (let ((max-borrow (unwrap-panic max-borrow-result)))
              (asserts! (<= (+ amount-to-borrow total-debt) max-borrow)
                ERR_BORROW_LIMIT_EXCEEDED
              )
              ;; Update vault
              (map-set vaults { owner: user } {
                collateral-amount: (get collateral-amount updated-vault),
                borrowed-amount: (+ (get borrowed-amount updated-vault) amount-to-borrow),
                interest-accumulated: (get interest-accumulated updated-vault),
                last-interest-update: stacks-block-height,
              })
              ;; Update total borrowed
              (var-set total-borrowed
                (+ (var-get total-borrowed) amount-to-borrow)
              )
              (ok amount-to-borrow)
            )
          )
        )
      )
    )
  )
)

;; Repay borrowed funds with interest
(define-public (repay (amount-to-repay uint))
  (let (
      (user tx-sender)
      (vault-data-option (map-get? vaults { owner: user }))
    )
    (begin
      (try! (assert-not-paused))
      (asserts! (> amount-to-repay u0) ERR_INVALID_AMOUNT)
      (asserts! (is-some vault-data-option) ERR_VAULT_NOT_FOUND)
      (let (
          (vault-data (unwrap-panic vault-data-option))
          (updated-vault (update-interest vault-data))
        )
        (let ((total-debt (+ (get borrowed-amount updated-vault)
            (get interest-accumulated updated-vault)
          )))
          ;; Ensure repayment amount doesn't exceed debt
          (let ((effective-repayment (if (> amount-to-repay total-debt)
              total-debt
              amount-to-repay
            )))
            ;; Calculate how much goes to interest vs principal
            (let (
                (interest-payment (if (> (get interest-accumulated updated-vault) effective-repayment)
                  effective-repayment
                  (get interest-accumulated updated-vault)
                ))
                (principal-payment (- effective-repayment interest-payment))
              )
              ;; Calculate protocol fee
              (let ((fee-amount (mul-div interest-payment (var-get protocol-fee-rate) u100)))
                ;; Update protocol statistics
                (var-set total-fees-collected
                  (+ (var-get total-fees-collected) (unwrap-panic fee-amount))
                )
                (var-set total-borrowed
                  (- (var-get total-borrowed) principal-payment)
                )
                ;; Update vault
                (map-set vaults { owner: user } {
                  collateral-amount: (get collateral-amount updated-vault),
                  borrowed-amount: (- (get borrowed-amount updated-vault) principal-payment),
                  interest-accumulated: (- (get interest-accumulated updated-vault) interest-payment),
                  last-interest-update: stacks-block-height,
                })
                (ok effective-repayment)
              )
            )
          )
        )
      )
    )
  )
)