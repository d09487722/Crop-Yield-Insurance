(define-trait insurance-trait (
    (get-policy-details
        (uint)
        (response {
            premium: uint,
            coverage: uint,
            start-block: uint,
            end-block: uint,
            status: (string-ascii 20),
        } uint)
    )
    (submit-claim
        (uint)
        (response bool uint)
    )
))

(define-data-var contract-owner principal tx-sender)
(define-data-var policy-counter uint u0)
(define-data-var total-premiums uint u0)
(define-data-var total-claims-paid uint u0)
(define-data-var oracle-address principal tx-sender)
(define-data-var minimum-premium uint u1000000)
(define-data-var maximum-coverage uint u10000000000)

(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-POLICY (err u101))
(define-constant ERR-POLICY-EXPIRED (err u102))
(define-constant ERR-POLICY-NOT-ACTIVE (err u103))
(define-constant ERR-INSUFFICIENT-FUNDS (err u104))
(define-constant ERR-CLAIM-ALREADY-SUBMITTED (err u105))
(define-constant ERR-INVALID-YIELD-DATA (err u106))
(define-constant ERR-POLICY-NOT-FOUND (err u107))
(define-constant ERR-INVALID-PARAMETERS (err u108))
(define-constant ERR-ORACLE-NOT-SET (err u109))

(define-map policies
    uint
    {
        farmer: principal,
        crop-type: (string-ascii 50),
        expected-yield: uint,
        coverage-amount: uint,
        premium-amount: uint,
        start-block: uint,
        end-block: uint,
        status: (string-ascii 20),
        claim-submitted: bool,
        actual-yield: (optional uint),
        payout-amount: (optional uint),
    }
)

(define-map farmer-policies
    principal
    (list 20 uint)
)

(define-map yield-reports
    {
        policy-id: uint,
        report-block: uint,
    }
    {
        reporter: principal,
        actual-yield: uint,
        verified: bool,
        timestamp: uint,
    }
)

(define-map oracle-whitelist
    principal
    bool
)

(define-public (set-oracle-address (new-oracle principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (var-set oracle-address new-oracle)
        (map-set oracle-whitelist new-oracle true)
        (ok true)
    )
)

(define-public (add-oracle (oracle principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (map-set oracle-whitelist oracle true)
        (ok true)
    )
)

(define-public (remove-oracle (oracle principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (map-delete oracle-whitelist oracle)
        (ok true)
    )
)

(define-public (create-policy
        (crop-type (string-ascii 50))
        (expected-yield uint)
        (coverage-amount uint)
        (duration-blocks uint)
    )
    (let (
            (policy-id (+ (var-get policy-counter) u1))
            (premium (calculate-premium coverage-amount duration-blocks expected-yield))
            (current-block stacks-block-height)
            (end-block (+ current-block duration-blocks))
        )
        (asserts! (>= coverage-amount (var-get minimum-premium))
            ERR-INVALID-PARAMETERS
        )
        (asserts! (<= coverage-amount (var-get maximum-coverage))
            ERR-INVALID-PARAMETERS
        )
        (asserts! (> expected-yield u0) ERR-INVALID-PARAMETERS)
        (asserts! (> duration-blocks u0) ERR-INVALID-PARAMETERS)

        (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))

        (map-set policies policy-id {
            farmer: tx-sender,
            crop-type: crop-type,
            expected-yield: expected-yield,
            coverage-amount: coverage-amount,
            premium-amount: premium,
            start-block: current-block,
            end-block: end-block,
            status: "active",
            claim-submitted: false,
            actual-yield: none,
            payout-amount: none,
        })

        (map-set farmer-policies tx-sender
            (unwrap!
                (as-max-len?
                    (append
                        (default-to (list) (map-get? farmer-policies tx-sender))
                        policy-id
                    )
                    u20
                )
                ERR-INVALID-PARAMETERS
            ))

        (var-set policy-counter policy-id)
        (var-set total-premiums (+ (var-get total-premiums) premium))
        (ok policy-id)
    )
)

(define-private (calculate-premium
        (coverage uint)
        (duration uint)
        (expected-yield uint)
    )
    (let (
            (base-rate u50)
            (risk-factor (/ coverage expected-yield))
            (time-factor (/ duration u144))
        )
        (/ (* coverage (+ base-rate (* risk-factor time-factor))) u10000)
    )
)

(define-public (submit-yield-report
        (policy-id uint)
        (actual-yield uint)
    )
    (let (
            (policy (unwrap! (map-get? policies policy-id) ERR-POLICY-NOT-FOUND))
            (current-block stacks-block-height)
        )
        (asserts! (default-to false (map-get? oracle-whitelist tx-sender))
            ERR-NOT-AUTHORIZED
        )
        (asserts! (is-eq (get status policy) "active") ERR-POLICY-NOT-ACTIVE)
        (asserts! (>= current-block (get end-block policy)) ERR-POLICY-EXPIRED)
        (asserts! (> actual-yield u0) ERR-INVALID-YIELD-DATA)

        (map-set yield-reports {
            policy-id: policy-id,
            report-block: current-block,
        } {
            reporter: tx-sender,
            actual-yield: actual-yield,
            verified: true,
            timestamp: current-block,
        })

        (map-set policies policy-id
            (merge policy {
                actual-yield: (some actual-yield),
                status: "reported",
            })
        )
        (ok true)
    )
)

(define-public (submit-claim (policy-id uint))
    (let (
            (policy (unwrap! (map-get? policies policy-id) ERR-POLICY-NOT-FOUND))
            (farmer (get farmer policy))
            (current-block stacks-block-height)
        )
        (asserts! (is-eq tx-sender farmer) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status policy) "reported") ERR-POLICY-NOT-ACTIVE)
        (asserts! (not (get claim-submitted policy)) ERR-CLAIM-ALREADY-SUBMITTED)
        (asserts! (<= current-block (+ (get end-block policy) u1008))
            ERR-POLICY-EXPIRED
        )

        (let (
                (actual-yield (unwrap! (get actual-yield policy) ERR-INVALID-YIELD-DATA))
                (expected-yield (get expected-yield policy))
                (coverage (get coverage-amount policy))
                (payout (calculate-payout actual-yield expected-yield coverage))
            )
            (map-set policies policy-id
                (merge policy {
                    claim-submitted: true,
                    payout-amount: (some payout),
                    status: "claimed",
                })
            )

            (if (> payout u0)
                (begin
                    (try! (as-contract (stx-transfer? payout tx-sender farmer)))
                    (var-set total-claims-paid
                        (+ (var-get total-claims-paid) payout)
                    )
                    (ok payout)
                )
                (ok u0)
            )
        )
    )
)

(define-private (calculate-payout
        (actual-yield uint)
        (expected-yield uint)
        (coverage uint)
    )
    (if (<= actual-yield (/ (* expected-yield u75) u100))
        (let (
                (yield-loss (- expected-yield actual-yield))
                (loss-percentage (/ (* yield-loss u100) expected-yield))
            )
            (if (>= loss-percentage u25)
                (/ (* coverage loss-percentage) u100)
                u0
            )
        )
        u0
    )
)

(define-public (get-policy (policy-id uint))
    (ok (map-get? policies policy-id))
)

(define-public (get-farmer-policies (farmer principal))
    (ok (default-to (list) (map-get? farmer-policies farmer)))
)

(define-public (get-yield-report
        (policy-id uint)
        (report-block uint)
    )
    (ok (map-get? yield-reports {
        policy-id: policy-id,
        report-block: report-block,
    }))
)

(define-public (cancel-policy (policy-id uint))
    (let (
            (policy (unwrap! (map-get? policies policy-id) ERR-POLICY-NOT-FOUND))
            (farmer (get farmer policy))
            (current-block stacks-block-height)
        )
        (asserts! (is-eq tx-sender farmer) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status policy) "active") ERR-POLICY-NOT-ACTIVE)
        (asserts! (< current-block (+ (get start-block policy) u144))
            ERR-POLICY-EXPIRED
        )

        (let ((refund-amount (/ (* (get premium-amount policy) u90) u100)))
            (map-set policies policy-id (merge policy { status: "cancelled" }))
            (try! (as-contract (stx-transfer? refund-amount tx-sender farmer)))
            (ok refund-amount)
        )
    )
)

(define-public (update-policy-parameters
        (min-premium uint)
        (max-coverage uint)
    )
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (> min-premium u0) ERR-INVALID-PARAMETERS)
        (asserts! (> max-coverage min-premium) ERR-INVALID-PARAMETERS)
        (var-set minimum-premium min-premium)
        (var-set maximum-coverage max-coverage)
        (ok true)
    )
)

(define-public (verify-yield-report
        (policy-id uint)
        (report-block uint)
        (verified bool)
    )
    (let (
            (report-key {
                policy-id: policy-id,
                report-block: report-block,
            })
            (existing-report (unwrap! (map-get? yield-reports report-key) ERR-INVALID-YIELD-DATA))
        )
        (asserts! (default-to false (map-get? oracle-whitelist tx-sender))
            ERR-NOT-AUTHORIZED
        )
        (map-set yield-reports report-key
            (merge existing-report { verified: verified })
        )
        (ok true)
    )
)

(define-public (emergency-pause (policy-id uint))
    (let ((policy (unwrap! (map-get? policies policy-id) ERR-POLICY-NOT-FOUND)))
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (map-set policies policy-id (merge policy { status: "paused" }))
        (ok true)
    )
)

(define-public (resume-policy (policy-id uint))
    (let ((policy (unwrap! (map-get? policies policy-id) ERR-POLICY-NOT-FOUND)))
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status policy) "paused") ERR-POLICY-NOT-ACTIVE)
        (map-set policies policy-id (merge policy { status: "active" }))
        (ok true)
    )
)

(define-public (transfer-ownership (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (var-set contract-owner new-owner)
        (ok true)
    )
)

(define-public (withdraw-excess-funds (amount uint))
    (let (
            (contract-balance (stx-get-balance (as-contract tx-sender)))
            (reserved-funds (+ (var-get total-premiums) (var-get total-claims-paid)))
        )
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (<= amount (- contract-balance reserved-funds))
            ERR-INSUFFICIENT-FUNDS
        )
        (try! (as-contract (stx-transfer? amount tx-sender (var-get contract-owner))))
        (ok amount)
    )
)

(define-read-only (get-contract-stats)
    (ok {
        total-policies: (var-get policy-counter),
        total-premiums: (var-get total-premiums),
        total-claims-paid: (var-get total-claims-paid),
        contract-balance: (stx-get-balance (as-contract tx-sender)),
        current-block: stacks-block-height,
    })
)

(define-read-only (get-policy-status (policy-id uint))
    (match (map-get? policies policy-id)
        policy (ok {
            status: (get status policy),
            farmer: (get farmer policy),
            coverage: (get coverage-amount policy),
            premium: (get premium-amount policy),
            blocks-remaining: (if (> (get end-block policy) stacks-block-height)
                (- (get end-block policy) stacks-block-height)
                u0
            ),
        })
        ERR-POLICY-NOT-FOUND
    )
)

(define-read-only (calculate-policy-premium
        (coverage uint)
        (duration uint)
        (expected-yield uint)
    )
    (ok (calculate-premium coverage duration expected-yield))
)

(define-read-only (is-policy-claimable (policy-id uint))
    (match (map-get? policies policy-id)
        policy (ok (and
            (is-eq (get status policy) "reported")
            (not (get claim-submitted policy))
            (<= stacks-block-height (+ (get end-block policy) u1008))
            (is-some (get actual-yield policy))
        ))
        ERR-POLICY-NOT-FOUND
    )
)

(define-read-only (get-owner)
    (ok (var-get contract-owner))
)

(define-read-only (get-oracle-address)
    (ok (var-get oracle-address))
)

(define-read-only (is-oracle (address principal))
    (ok (default-to false (map-get? oracle-whitelist address)))
)

(define-read-only (get-minimum-premium)
    (ok (var-get minimum-premium))
)

(define-read-only (get-maximum-coverage)
    (ok (var-get maximum-coverage))
)

(define-public (batch-create-policies (policies-data (list 10
    {
    crop-type: (string-ascii 50),
    expected-yield: uint,
    coverage-amount: uint,
    duration-blocks: uint,
})))
    (let ((total-premium (fold calculate-batch-premium policies-data u0)))
        (try! (stx-transfer? total-premium tx-sender (as-contract tx-sender)))
        (ok (map create-single-policy policies-data))
    )
)

(define-private (calculate-batch-premium
        (policy-data {
            crop-type: (string-ascii 50),
            expected-yield: uint,
            coverage-amount: uint,
            duration-blocks: uint,
        })
        (acc uint)
    )
    (+ acc
        (calculate-premium (get coverage-amount policy-data)
            (get duration-blocks policy-data)
            (get expected-yield policy-data)
        ))
)

(define-private (create-single-policy (policy-data {
    crop-type: (string-ascii 50),
    expected-yield: uint,
    coverage-amount: uint,
    duration-blocks: uint,
}))
    (let (
            (policy-id (+ (var-get policy-counter) u1))
            (premium (calculate-premium (get coverage-amount policy-data)
                (get duration-blocks policy-data)
                (get expected-yield policy-data)
            ))
            (current-block stacks-block-height)
            (end-block (+ current-block (get duration-blocks policy-data)))
        )
        (map-set policies policy-id {
            farmer: tx-sender,
            crop-type: (get crop-type policy-data),
            expected-yield: (get expected-yield policy-data),
            coverage-amount: (get coverage-amount policy-data),
            premium-amount: premium,
            start-block: current-block,
            end-block: end-block,
            status: "active",
            claim-submitted: false,
            actual-yield: none,
            payout-amount: none,
        })
        (var-set policy-counter policy-id)
        policy-id
    )
)
