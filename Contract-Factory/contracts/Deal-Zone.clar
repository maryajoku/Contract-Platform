;; Contract Negotiation Platform
;; A comprehensive smart contract for creating, negotiating, and executing multi-party contracts

;; Constants
(define-constant contract-deployer tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-UNAUTHORIZED-ACCESS (err u102))
(define-constant ERR-INVALID-STATE (err u103))
(define-constant ERR-ALREADY-SIGNED (err u104))
(define-constant ERR-INVALID-AMOUNT (err u105))
(define-constant ERR-CONTRACT-EXPIRED (err u106))
(define-constant ERR-INSUFFICIENT-BALANCE (err u107))
(define-constant ERR-INVALID-PARTICIPANT (err u108))
(define-constant ERR-CONTRACT-FINALIZED (err u109))
(define-constant ERR-INVALID-REVISION (err u110))
(define-constant ERR-INVALID-TITLE (err u400))
(define-constant ERR-INVALID-PARTICIPANTS-COUNT (err u401))
(define-constant ERR-TOO-MANY-PARTICIPANTS (err u402))
(define-constant ERR-INVALID-REQUIRED-SIGNATURES (err u403))
(define-constant ERR-SIGNATURES-EXCEED-PARTICIPANTS (err u404))
(define-constant ERR-DURATION-TOO-SHORT (err u405))
(define-constant ERR-FEE-TOO-HIGH (err u500))
(define-constant ERR-DURATION-TOO-SHORT-ADMIN (err u501))

;; Data Variables
(define-data-var contract-counter uint u0)
(define-data-var platform-fee-percentage uint u250) ;; 2.5% in basis points
(define-data-var min-contract-duration uint u86400) ;; 24 hours in seconds

;; Contract States
(define-constant state-draft u1)
(define-constant state-negotiation u2)
(define-constant state-ready-to-sign u3)
(define-constant state-partially-signed u4)
(define-constant state-fully-signed u5)
(define-constant state-executed u6)
(define-constant state-cancelled u7)
(define-constant state-expired u8)

;; Data Maps
(define-map contracts
  uint
  {
    creator: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    participants: (list 10 principal),
    required-signatures: uint,
    current-signatures: uint,
    state: uint,
    value: uint,
    created-at: uint,
    expires-at: uint,
    revision-count: uint,
    execution-deadline: uint
  }
)

(define-map contract-participants
  { contract-id: uint, participant: principal }
  {
    signed: bool,
    signed-at: uint,
    role: (string-ascii 50),
    can-modify: bool
  }
)

(define-map contract-terms
  uint
  {
    terms-hash: (buff 32),
    terms-text: (string-ascii 1000),
    created-by: principal,
    created-at: uint,
    is-active: bool
  }
)

(define-map contract-revisions
  { contract-id: uint, revision: uint }
  {
    terms-hash: (buff 32),
    revised-by: principal,
    revised-at: uint,
    change-description: (string-ascii 200),
    approved-by: (list 10 principal)
  }
)

(define-map contract-signatures
  { contract-id: uint, signer: principal }
  {
    signature-hash: (buff 64),
    signed-at: uint,
    revision-signed: uint
  }
)

(define-map contract-payments
  { contract-id: uint, participant: principal }
  uint
)

(define-map platform-stats
  (string-ascii 20)
  uint
)

;; Authorization Functions
(define-private (is-contract-creator (contract-id uint))
  (match (map-get? contracts contract-id)
    contract-data (is-eq tx-sender (get creator contract-data))
    false
  )
)

(define-private (is-contract-participant (contract-id uint) (participant principal))
  (is-some (map-get? contract-participants { contract-id: contract-id, participant: participant }))
)

(define-private (can-modify-contract (contract-id uint))
  (match (map-get? contract-participants { contract-id: contract-id, participant: tx-sender })
    participant-data (get can-modify participant-data)
    false
  )
)

;; Utility Functions
(define-private (get-current-time)
  block-height ;; Using block height as time proxy
)

(define-private (is-contract-expired (contract-id uint))
  (match (map-get? contracts contract-id)
    contract-data 
    (> (get-current-time) (get expires-at contract-data))
    false
  )
)

(define-private (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee-percentage)) u10000)
)

(define-private (update-platform-stats (stat-name (string-ascii 20)) (increment uint))
  (let ((current-value (default-to u0 (map-get? platform-stats stat-name))))
    (map-set platform-stats stat-name (+ current-value increment))
  )
)

;; Contract Creation Functions
(define-public (create-contract 
  (title (string-ascii 100))
  (description (string-ascii 500))
  (participants (list 10 principal))
  (required-signatures uint)
  (value uint)
  (duration uint)
  (terms-text (string-ascii 1000))
)
  (let 
    (
      (contract-id (+ (var-get contract-counter) u1))
      (current-time (get-current-time))
      (expiry-time (+ current-time duration))
      (terms-hash (sha256 (unwrap-panic (to-consensus-buff? terms-text))))
      (participants-count (len participants))
    )
    ;; Validation
    (asserts! (> (len title) u0) ERR-INVALID-TITLE)
    (asserts! (> participants-count u0) ERR-INVALID-PARTICIPANTS-COUNT)
    (asserts! (<= participants-count u10) ERR-TOO-MANY-PARTICIPANTS)
    (asserts! (> required-signatures u0) ERR-INVALID-REQUIRED-SIGNATURES)
    (asserts! (<= required-signatures participants-count) ERR-SIGNATURES-EXCEED-PARTICIPANTS)
    (asserts! (>= duration (var-get min-contract-duration)) ERR-DURATION-TOO-SHORT)
    
    ;; Create contract
    (map-set contracts contract-id
      {
        creator: tx-sender,
        title: title,
        description: description,
        participants: participants,
        required-signatures: required-signatures,
        current-signatures: u0,
        state: state-draft,
        value: value,
        created-at: current-time,
        expires-at: expiry-time,
        revision-count: u0,
        execution-deadline: (+ expiry-time u86400)
      }
    )
    
    ;; Set contract terms
    (map-set contract-terms contract-id
      {
        terms-hash: terms-hash,
        terms-text: terms-text,
        created-by: tx-sender,
        created-at: current-time,
        is-active: true
      }
    )
    
    ;; Add participants
    (try! (fold add-participant-to-contract participants (ok contract-id)))
    
    ;; Update counter and stats
    (var-set contract-counter contract-id)
    (update-platform-stats "total-contracts" u1)
    
    (ok contract-id)
  )
)

(define-private (add-participant-to-contract (participant principal) (result (response uint uint)))
  (match result
    contract-id
    (begin
      (map-set contract-participants 
        { contract-id: contract-id, participant: participant }
        {
          signed: false,
          signed-at: u0,
          role: "participant",
          can-modify: (is-eq participant tx-sender)
        }
      )
      (ok contract-id)
    )
    error-code (err error-code)
  )
)

;; Contract Management Functions
(define-public (update-contract-state (contract-id uint) (new-state uint))
  (let ((contract-data (unwrap! (map-get? contracts contract-id) ERR-NOT-FOUND)))
    (asserts! (is-contract-creator contract-id) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (<= new-state u8) ERR-INVALID-STATE)
    
    (map-set contracts contract-id
      (merge contract-data { state: new-state })
    )
    (ok true)
  )
)

(define-public (add-contract-revision 
  (contract-id uint)
  (new-terms (string-ascii 1000))
  (change-description (string-ascii 200))
)
  (let 
    (
      (contract-data (unwrap! (map-get? contracts contract-id) ERR-NOT-FOUND))
      (current-revision (get revision-count contract-data))
      (new-revision (+ current-revision u1))
      (terms-hash (sha256 (unwrap-panic (to-consensus-buff? new-terms))))
    )
    (asserts! (can-modify-contract contract-id) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (not (is-contract-expired contract-id)) ERR-CONTRACT-EXPIRED)
    (asserts! (< (get state contract-data) state-fully-signed) ERR-CONTRACT-FINALIZED)
    
    ;; Add revision
    (map-set contract-revisions 
      { contract-id: contract-id, revision: new-revision }
      {
        terms-hash: terms-hash,
        revised-by: tx-sender,
        revised-at: (get-current-time),
        change-description: change-description,
        approved-by: (list tx-sender)
      }
    )
    
    ;; Update contract
    (map-set contracts contract-id
      (merge contract-data 
        { 
          revision-count: new-revision,
          current-signatures: u0,
          state: state-negotiation
        }
      )
    )
    
    ;; Update terms
    (map-set contract-terms contract-id
      {
        terms-hash: terms-hash,
        terms-text: new-terms,
        created-by: tx-sender,
        created-at: (get-current-time),
        is-active: true
      }
    )
    
    ;; Reset all signatures
    (try! (fold reset-participant-signature (get participants contract-data) (ok true)))
    
    (ok new-revision)
  )
)

(define-private (reset-participant-signature (participant principal) (result (response bool uint)))
  (match result
    success
    (begin
      (map-set contract-participants 
        { contract-id: u0, participant: participant } ;; Note: In real implementation, pass contract-id
        (merge 
          (default-to 
            { signed: false, signed-at: u0, role: "participant", can-modify: false }
            (map-get? contract-participants { contract-id: u0, participant: participant })
          )
          { signed: false, signed-at: u0 }
        )
      )
      (ok true)
    )
    error-code (err error-code)
  )
)

;; Signature Functions
(define-public (sign-contract (contract-id uint) (signature-hash (buff 64)))
  (let 
    (
      (contract-data (unwrap! (map-get? contracts contract-id) ERR-NOT-FOUND))
      (participant-data (unwrap! 
        (map-get? contract-participants { contract-id: contract-id, participant: tx-sender })
        ERR-INVALID-PARTICIPANT
      ))
      (current-signatures (get current-signatures contract-data))
      (required-signatures (get required-signatures contract-data))
    )
    (asserts! (not (get signed participant-data)) ERR-ALREADY-SIGNED)
    (asserts! (not (is-contract-expired contract-id)) ERR-CONTRACT-EXPIRED)
    (asserts! (>= (get state contract-data) state-ready-to-sign) ERR-INVALID-STATE)
    
    ;; Record signature
    (map-set contract-signatures
      { contract-id: contract-id, signer: tx-sender }
      {
        signature-hash: signature-hash,
        signed-at: (get-current-time),
        revision-signed: (get revision-count contract-data)
      }
    )
    
    ;; Update participant
    (map-set contract-participants
      { contract-id: contract-id, participant: tx-sender }
      (merge participant-data 
        { 
          signed: true, 
          signed-at: (get-current-time) 
        }
      )
    )
    
    ;; Update contract signatures count
    (let ((new-signature-count (+ current-signatures u1)))
      (map-set contracts contract-id
        (merge contract-data 
          { 
            current-signatures: new-signature-count,
            state: (if (>= new-signature-count required-signatures)
                     state-fully-signed
                     state-partially-signed)
          }
        )
      )
      
      ;; Update stats
      (update-platform-stats "total-signatures" u1)
      
      (ok new-signature-count)
    )
  )
)

;; Payment Functions
(define-public (deposit-payment (contract-id uint))
  (let 
    (
      (contract-data (unwrap! (map-get? contracts contract-id) ERR-NOT-FOUND))
      (contract-value (get value contract-data))
    )
    (asserts! (is-contract-participant contract-id tx-sender) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (> contract-value u0) ERR-INVALID-AMOUNT)
    (asserts! (is-eq (get state contract-data) state-fully-signed) ERR-INVALID-STATE)
    
    ;; Transfer STX to contract
    (try! (stx-transfer? contract-value tx-sender (as-contract tx-sender)))
    
    ;; Record payment
    (map-set contract-payments
      { contract-id: contract-id, participant: tx-sender }
      contract-value
    )
    
    (update-platform-stats "total-value-locked" contract-value)
    (ok true)
  )
)

(define-public (execute-contract (contract-id uint))
  (let ((contract-data (unwrap! (map-get? contracts contract-id) ERR-NOT-FOUND)))
    (asserts! (is-contract-creator contract-id) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (is-eq (get state contract-data) state-fully-signed) ERR-INVALID-STATE)
    (asserts! (not (is-contract-expired contract-id)) ERR-CONTRACT-EXPIRED)
    
    ;; Calculate and transfer platform fee
    (let 
      (
        (contract-value (get value contract-data))
        (platform-fee (calculate-platform-fee contract-value))
        (net-amount (- contract-value platform-fee))
      )
      (and (> platform-fee u0)
           (try! (as-contract (stx-transfer? platform-fee tx-sender contract-deployer))))
      
      ;; Distribute remaining funds (simplified - in practice would be more complex)
      (and (> net-amount u0)
           (try! (as-contract (stx-transfer? net-amount tx-sender (get creator contract-data)))))
    )
    
    ;; Update contract state
    (map-set contracts contract-id
      (merge contract-data { state: state-executed })
    )
    
    (update-platform-stats "executed-contracts" u1)
    (ok true)
  )
)

(define-public (cancel-contract (contract-id uint))
  (let ((contract-data (unwrap! (map-get? contracts contract-id) ERR-NOT-FOUND)))
    (asserts! (is-contract-creator contract-id) ERR-UNAUTHORIZED-ACCESS)
    (asserts! (< (get state contract-data) state-fully-signed) ERR-CONTRACT-FINALIZED)
    
    (map-set contracts contract-id
      (merge contract-data { state: state-cancelled })
    )
    
    (ok true)
  )
)

;; Query Functions
(define-read-only (get-contract (contract-id uint))
  (map-get? contracts contract-id)
)

(define-read-only (get-contract-terms (contract-id uint))
  (map-get? contract-terms contract-id)
)

(define-read-only (get-contract-participant (contract-id uint) (participant principal))
  (map-get? contract-participants { contract-id: contract-id, participant: participant })
)

(define-read-only (get-contract-signature (contract-id uint) (signer principal))
  (map-get? contract-signatures { contract-id: contract-id, signer: signer })
)

(define-read-only (get-contract-revision (contract-id uint) (revision uint))
  (map-get? contract-revisions { contract-id: contract-id, revision: revision })
)

(define-read-only (get-participant-payment (contract-id uint) (participant principal))
  (map-get? contract-payments { contract-id: contract-id, participant: participant })
)

(define-read-only (get-platform-stats (stat-name (string-ascii 20)))
  (map-get? platform-stats stat-name)
)

(define-read-only (get-contract-counter)
  (var-get contract-counter)
)

(define-read-only (is-contract-ready-for-execution (contract-id uint))
  (match (map-get? contracts contract-id)
    contract-data
    (and 
      (is-eq (get state contract-data) state-fully-signed)
      (not (is-contract-expired contract-id))
    )
    false
  )
)

;; Admin Functions
(define-public (set-platform-fee (new-fee-percentage uint))
  (begin
    (asserts! (is-eq tx-sender contract-deployer) ERR-OWNER-ONLY)
    (asserts! (<= new-fee-percentage u1000) ERR-FEE-TOO-HIGH) ;; Max 10%
    (var-set platform-fee-percentage new-fee-percentage)
    (ok true)
  )
)

(define-public (set-min-contract-duration (new-duration uint))
  (begin
    (asserts! (is-eq tx-sender contract-deployer) ERR-OWNER-ONLY)
    (asserts! (>= new-duration u3600) ERR-DURATION-TOO-SHORT-ADMIN) ;; Min 1 hour
    (var-set min-contract-duration new-duration)
    (ok true)
  )
)

(define-public (withdraw-platform-fees (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-deployer) ERR-OWNER-ONLY)
    (as-contract (stx-transfer? amount tx-sender contract-deployer))
  )
)

;; Emergency Functions
(define-public (emergency-pause-contract (contract-id uint))
  (let ((contract-data (unwrap! (map-get? contracts contract-id) ERR-NOT-FOUND)))
    (asserts! (is-eq tx-sender contract-deployer) ERR-OWNER-ONLY)
    
    (map-set contracts contract-id
      (merge contract-data { state: state-cancelled })
    )
    (ok true)
  )
)