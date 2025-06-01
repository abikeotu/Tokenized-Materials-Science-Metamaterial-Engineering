;; Design Protocol Contract
;; Manages metamaterial design specifications and collaboration

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-not-found (err u201))
(define-constant err-unauthorized (err u202))
(define-constant err-invalid-version (err u203))

;; Data Variables
(define-data-var next-design-id uint u1)
(define-data-var next-version-id uint u1)

;; Data Maps
(define-map designs
  { design-id: uint }
  {
    creator: principal,
    name: (string-ascii 50),
    description: (string-ascii 300),
    category: (string-ascii 30),
    license-type: (string-ascii 20),
    created-at: uint,
    is-public: bool
  }
)

(define-map design-versions
  { design-id: uint, version-id: uint }
  {
    author: principal,
    parameters: (string-ascii 500),
    performance-metrics: (string-ascii 200),
    changelog: (string-ascii 300),
    created-at: uint
  }
)

(define-map design-collaborators
  { design-id: uint, collaborator: principal }
  { permissions: (string-ascii 20), added-at: uint }
)

(define-map design-tokens
  { holder: principal }
  { balance: uint }
)

(define-map design-ratings
  { design-id: uint, rater: principal }
  { rating: uint, feedback: (string-ascii 200) }
)

;; Public Functions

;; Create new design
(define-public (create-design (name (string-ascii 50)) (description (string-ascii 300)) (category (string-ascii 30)))
  (let
    (
      (design-id (var-get next-design-id))
      (version-id (var-get next-version-id))
    )
    ;; Create design entry
    (map-set designs
      { design-id: design-id }
      {
        creator: tx-sender,
        name: name,
        description: description,
        category: category,
        license-type: "open",
        created-at: block-height,
        is-public: true
      }
    )

    ;; Create initial version
    (map-set design-versions
      { design-id: design-id, version-id: u1 }
      {
        author: tx-sender,
        parameters: "initial-parameters",
        performance-metrics: "baseline-metrics",
        changelog: "Initial design creation",
        created-at: block-height
      }
    )

    ;; Mint design tokens for creator
    (mint-design-tokens tx-sender u100)

    ;; Update counters
    (var-set next-design-id (+ design-id u1))
    (var-set next-version-id (+ version-id u1))

    (ok design-id)
  )
)

;; Add new version to existing design
(define-public (add-design-version (design-id uint) (parameters (string-ascii 500)) (performance-metrics (string-ascii 200)) (changelog (string-ascii 300)))
  (let
    (
      (design-data (unwrap! (map-get? designs { design-id: design-id }) err-not-found))
      (version-id (var-get next-version-id))
    )
    ;; Check if user can modify this design
    (asserts! (or (is-eq tx-sender (get creator design-data))
                  (is-collaborator design-id tx-sender)) err-unauthorized)

    ;; Add new version
    (map-set design-versions
      { design-id: design-id, version-id: version-id }
      {
        author: tx-sender,
        parameters: parameters,
        performance-metrics: performance-metrics,
        changelog: changelog,
        created-at: block-height
      }
    )

    ;; Reward contributor
    (mint-design-tokens tx-sender u50)

    (var-set next-version-id (+ version-id u1))

    (ok version-id)
  )
)

;; Add collaborator to design
(define-public (add-collaborator (design-id uint) (collaborator principal) (permissions (string-ascii 20)))
  (let
    (
      (design-data (unwrap! (map-get? designs { design-id: design-id }) err-not-found))
    )
    (asserts! (is-eq tx-sender (get creator design-data)) err-unauthorized)

    (map-set design-collaborators
      { design-id: design-id, collaborator: collaborator }
      { permissions: permissions, added-at: block-height }
    )

    (ok true)
  )
)

;; Rate a design
(define-public (rate-design (design-id uint) (rating uint) (feedback (string-ascii 200)))
  (begin
    (asserts! (<= rating u10) (err u204)) ;; Rating must be 1-10

    (map-set design-ratings
      { design-id: design-id, rater: tx-sender }
      { rating: rating, feedback: feedback }
    )

    (ok true)
  )
)

;; Read-only Functions

(define-read-only (get-design (design-id uint))
  (map-get? designs { design-id: design-id })
)

(define-read-only (get-design-version (design-id uint) (version-id uint))
  (map-get? design-versions { design-id: design-id, version-id: version-id })
)

(define-read-only (get-design-token-balance (holder principal))
  (default-to u0 (get balance (map-get? design-tokens { holder: holder })))
)

(define-read-only (is-collaborator (design-id uint) (user principal))
  (is-some (map-get? design-collaborators { design-id: design-id, collaborator: user }))
)

;; Private Functions

(define-private (mint-design-tokens (recipient principal) (amount uint))
  (let
    (
      (current-balance (get-design-token-balance recipient))
    )
    (map-set design-tokens
      { holder: recipient }
      { balance: (+ current-balance amount) }
    )
  )
)
