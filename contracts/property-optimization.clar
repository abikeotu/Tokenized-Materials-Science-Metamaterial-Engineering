;; Property Optimization Contract
;; Enhances metamaterial characteristics through optimization algorithms

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u300))
(define-constant err-not-found (err u301))
(define-constant err-invalid-improvement (err u302))
(define-constant err-insufficient-tokens (err u303))

;; Data Variables
(define-data-var next-optimization-id uint u1)
(define-data-var optimization-reward-rate uint u10)

;; Data Maps
(define-map optimizations
  { optimization-id: uint }
  {
    optimizer: principal,
    design-id: uint,
    property-type: (string-ascii 30),
    baseline-value: uint,
    optimized-value: uint,
    improvement-percentage: uint,
    algorithm-used: (string-ascii 50),
    created-at: uint,
    status: (string-ascii 20)
  }
)

(define-map optimization-parameters
  { optimization-id: uint }
  {
    parameters: (string-ascii 500),
    constraints: (string-ascii 300),
    objectives: (string-ascii 200)
  }
)

(define-map optimization-tokens
  { holder: principal }
  { balance: uint }
)

(define-map property-benchmarks
  { property-type: (string-ascii 30) }
  { best-value: uint, benchmark-holder: principal, set-at: uint }
)

;; Public Functions

;; Submit optimization
(define-public (submit-optimization
  (design-id uint)
  (property-type (string-ascii 30))
  (baseline-value uint)
  (optimized-value uint)
  (algorithm-used (string-ascii 50))
  (parameters (string-ascii 500)))
  (let
    (
      (optimization-id (var-get next-optimization-id))
      (improvement-pct (calculate-improvement-percentage baseline-value optimized-value))
    )
    (asserts! (> improvement-pct u0) err-invalid-improvement)

    ;; Store optimization
    (map-set optimizations
      { optimization-id: optimization-id }
      {
        optimizer: tx-sender,
        design-id: design-id,
        property-type: property-type,
        baseline-value: baseline-value,
        optimized-value: optimized-value,
        improvement-percentage: improvement-pct,
        algorithm-used: algorithm-used,
        created-at: block-height,
        status: "pending"
      }
    )

    ;; Store parameters
    (map-set optimization-parameters
      { optimization-id: optimization-id }
      {
        parameters: parameters,
        constraints: "standard-constraints",
        objectives: "maximize-performance"
      }
    )

    ;; Update benchmark if this is the best
    (update-benchmark property-type optimized-value tx-sender)

    (var-set next-optimization-id (+ optimization-id u1))

    (ok optimization-id)
  )
)

;; Validate optimization and reward
(define-public (validate-optimization (optimization-id uint) (is-valid bool))
  (let
    (
      (opt-data (unwrap! (map-get? optimizations { optimization-id: optimization-id }) err-not-found))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)

    (if is-valid
      (begin
        ;; Update status
        (map-set optimizations
          { optimization-id: optimization-id }
          (merge opt-data { status: "validated" })
        )

        ;; Reward optimizer
        (reward-optimization (get optimizer opt-data) (get improvement-percentage opt-data))

        (ok true)
      )
      (begin
        ;; Mark as invalid
        (map-set optimizations
          { optimization-id: optimization-id }
          (merge opt-data { status: "invalid" })
        )

        (ok false)
      )
    )
  )
)

;; Apply optimization to design
(define-public (apply-optimization (optimization-id uint) (target-design-id uint))
  (let
    (
      (opt-data (unwrap! (map-get? optimizations { optimization-id: optimization-id }) err-not-found))
      (token-cost u100)
    )
    (asserts! (>= (get-optimization-token-balance tx-sender) token-cost) err-insufficient-tokens)
    (asserts! (is-eq (get status opt-data) "validated") (err u304))

    ;; Deduct tokens
    (burn-optimization-tokens tx-sender token-cost)

    ;; Reward original optimizer
    (mint-optimization-tokens (get optimizer opt-data) u50)

    (ok true)
  )
)

;; Read-only Functions

(define-read-only (get-optimization (optimization-id uint))
  (map-get? optimizations { optimization-id: optimization-id })
)

(define-read-only (get-optimization-parameters (optimization-id uint))
  (map-get? optimization-parameters { optimization-id: optimization-id })
)

(define-read-only (get-optimization-token-balance (holder principal))
  (default-to u0 (get balance (map-get? optimization-tokens { holder: holder })))
)

(define-read-only (get-property-benchmark (property-type (string-ascii 30)))
  (map-get? property-benchmarks { property-type: property-type })
)

;; Private Functions

(define-private (calculate-improvement-percentage (baseline uint) (optimized uint))
  (if (> optimized baseline)
    (/ (* (- optimized baseline) u100) baseline)
    u0
  )
)

(define-private (update-benchmark (property-type (string-ascii 30)) (value uint) (holder principal))
  (let
    (
      (current-benchmark (map-get? property-benchmarks { property-type: property-type }))
    )
    (match current-benchmark
      benchmark
      (if (> value (get best-value benchmark))
        (map-set property-benchmarks
          { property-type: property-type }
          { best-value: value, benchmark-holder: holder, set-at: block-height }
        )
        false
      )
      ;; No existing benchmark
      (map-set property-benchmarks
        { property-type: property-type }
        { best-value: value, benchmark-holder: holder, set-at: block-height }
      )
    )
  )
)

(define-private (reward-optimization (optimizer principal) (improvement-pct uint))
  (let
    (
      (reward-amount (* improvement-pct (var-get optimization-reward-rate)))
    )
    (mint-optimization-tokens optimizer reward-amount)
  )
)

(define-private (mint-optimization-tokens (recipient principal) (amount uint))
  (let
    (
      (current-balance (get-optimization-token-balance recipient))
    )
    (map-set optimization-tokens
      { holder: recipient }
      { balance: (+ current-balance amount) }
    )
  )
)

(define-private (burn-optimization-tokens (holder principal) (amount uint))
  (let
    (
      (current-balance (get-optimization-token-balance holder))
    )
    (map-set optimization-tokens
      { holder: holder }
      { balance: (- current-balance amount) }
    )
  )
)
