;; title: health-predictor
;; version: 1.0.0
;; summary: AI-powered platform analyzing continuous biomarker data from wearables to predict health issues and reward users for maintaining healthy behaviors
;; description: This smart contract manages biomarker data collection, health predictions, and reward distribution for maintaining healthy behaviors

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INVALID_DATA (err u101))
(define-constant ERR_USER_NOT_FOUND (err u102))
(define-constant ERR_INSUFFICIENT_BALANCE (err u103))
(define-constant ERR_PREDICTION_FAILED (err u104))
(define-constant ERR_ALREADY_EXISTS (err u105))
(define-constant ERR_INVALID_PROVIDER (err u106))

;; Reward amounts
(define-constant DAILY_ACTIVITY_REWARD u100)
(define-constant WEEKLY_GOAL_REWARD u500)
(define-constant HEALTH_IMPROVEMENT_REWARD u1000)
(define-constant PERFECT_WEEK_BONUS u2000)

;; Health thresholds
(define-constant LOW_RISK_THRESHOLD u30)
(define-constant MODERATE_RISK_THRESHOLD u70)
(define-constant HIGH_RISK_THRESHOLD u90)

;; data vars
(define-data-var next-prediction-id uint u1)
(define-data-var total-users uint u0)
(define-data-var total-predictions uint u0)
(define-data-var contract-balance uint u0)
(define-data-var prediction-model-version uint u1)

;; data maps
(define-map users 
    principal 
    {
        registered-at: uint,
        total-rewards: uint,
        health-score: uint,
        risk-level: (string-ascii 20),
        active: bool,
        privacy-level: uint
    }
)

(define-map biomarker-data
    { user: principal, timestamp: uint }
    {
        heart-rate: uint,
        blood-pressure-sys: uint,
        blood-pressure-dia: uint,
        sleep-hours: uint,
        steps: uint,
        stress-level: uint,
        validated: bool,
        encrypted: bool
    }
)

(define-map health-predictions
    { user: principal, prediction-id: uint }
    {
        risk-score: uint,
        prediction-type: (string-ascii 50),
        confidence: uint,
        created-at: uint,
        recommendations: (string-ascii 200),
        severity: (string-ascii 20)
    }
)

(define-map healthcare-providers
    principal
    {
        name: (string-ascii 100),
        specialty: (string-ascii 50),
        licensed: bool,
        verified-at: uint,
        access-level: uint
    }
)

(define-map user-permissions
    { user: principal, provider: principal }
    {
        granted: bool,
        granted-at: uint,
        access-level: uint,
        expires-at: uint
    }
)

(define-map daily-activities
    { user: principal, date: uint }
    {
        goals-met: uint,
        total-goals: uint,
        activity-score: uint,
        reward-claimed: bool,
        bonus-eligible: bool
    }
)

;; Token balances for rewards
(define-map token-balances principal uint)

;; private functions
(define-private (is-contract-owner)
    (is-eq tx-sender CONTRACT_OWNER)
)

(define-private (calculate-health-score (heart-rate uint) (blood-pressure-sys uint) (sleep-hours uint) (steps uint) (stress-level uint))
    (let (
        (hr-score (if (and (>= heart-rate u60) (<= heart-rate u100)) u20 u0))
        (bp-score (if (and (>= blood-pressure-sys u90) (<= blood-pressure-sys u140)) u20 u0))
        (sleep-score (if (>= sleep-hours u7) u20 u0))
        (steps-score (if (>= steps u8000) u20 u0))
        (stress-score (if (<= stress-level u5) u20 u0))
    )
    (+ hr-score (+ bp-score (+ sleep-score (+ steps-score stress-score))))
    )
)

(define-private (determine-risk-level (health-score uint))
    (if (<= health-score LOW_RISK_THRESHOLD)
        "high-risk"
        (if (<= health-score MODERATE_RISK_THRESHOLD)
            "moderate-risk"
            "low-risk"
        )
    )
)

(define-private (generate-recommendations (risk-score uint))
    (if (>= risk-score HIGH_RISK_THRESHOLD)
        "Immediate medical attention recommended. Consult healthcare provider."
        (if (>= risk-score MODERATE_RISK_THRESHOLD)
            "Monitor closely. Consider lifestyle modifications and medical consultation."
            "Maintain healthy habits. Continue regular monitoring."
        )
    )
)

(define-private (validate-biomarker-ranges (heart-rate uint) (bp-sys uint) (bp-dia uint) (sleep-hours uint) (steps uint) (stress-level uint))
    (and 
        (and (>= heart-rate u30) (<= heart-rate u200))
        (and (>= bp-sys u70) (<= bp-sys u200))
        (and (>= bp-dia u40) (<= bp-dia u120))
        (and (<= sleep-hours u24))
        (and (<= steps u50000))
        (and (<= stress-level u10))
    )
)

;; public functions
(define-public (register-user (privacy-level uint))
    (let (
        (caller tx-sender)
        (current-block block-height)
    )
    (asserts! (is-none (map-get? users caller)) ERR_ALREADY_EXISTS)
    (asserts! (and (>= privacy-level u1) (<= privacy-level u5)) ERR_INVALID_DATA)
    
    (map-set users caller {
        registered-at: current-block,
        total-rewards: u0,
        health-score: u50,
        risk-level: "unknown",
        active: true,
        privacy-level: privacy-level
    })
    
    (map-set token-balances caller u0)
    (var-set total-users (+ (var-get total-users) u1))
    
    (ok caller)
    )
)

(define-public (submit-biomarker-data (heart-rate uint) (blood-pressure-sys uint) (blood-pressure-dia uint) 
                                     (sleep-hours uint) (steps uint) (stress-level uint) (encrypted bool))
    (let (
        (caller tx-sender)
        (timestamp block-height)
        (user-data (unwrap! (map-get? users caller) ERR_USER_NOT_FOUND))
    )
    (asserts! (get active user-data) ERR_NOT_AUTHORIZED)
    (asserts! (validate-biomarker-ranges heart-rate blood-pressure-sys blood-pressure-dia sleep-hours steps stress-level) ERR_INVALID_DATA)
    
    (map-set biomarker-data { user: caller, timestamp: timestamp } {
        heart-rate: heart-rate,
        blood-pressure-sys: blood-pressure-sys,
        blood-pressure-dia: blood-pressure-dia,
        sleep-hours: sleep-hours,
        steps: steps,
        stress-level: stress-level,
        validated: true,
        encrypted: encrypted
    })
    
    ;; Update user's health score
    (let (
        (new-health-score (calculate-health-score heart-rate blood-pressure-sys sleep-hours steps stress-level))
        (risk-level (determine-risk-level new-health-score))
    )
    (map-set users caller (merge user-data {
        health-score: new-health-score,
        risk-level: risk-level
    }))
    )
    
    (ok timestamp)
    )
)

(define-public (generate-health-prediction (user principal) (prediction-type (string-ascii 50)))
    (let (
        (caller tx-sender)
        (user-data (unwrap! (map-get? users user) ERR_USER_NOT_FOUND))
        (prediction-id (var-get next-prediction-id))
        (health-score (get health-score user-data))
    )
    ;; For now, simplified prediction based on health score
    (let (
        (risk-score (if (is-eq (get risk-level user-data) "high-risk") u85
                       (if (is-eq (get risk-level user-data) "moderate-risk") u55 u25)))
        (confidence (if (>= health-score u70) u90 u70))
        (recommendations (generate-recommendations risk-score))
        (severity (if (>= risk-score u70) "high" (if (>= risk-score u40) "medium" "low")))
    )
    
    (map-set health-predictions { user: user, prediction-id: prediction-id } {
        risk-score: risk-score,
        prediction-type: prediction-type,
        confidence: confidence,
        created-at: block-height,
        recommendations: recommendations,
        severity: severity
    })
    
    (var-set next-prediction-id (+ prediction-id u1))
    (var-set total-predictions (+ (var-get total-predictions) u1))
    
    (ok prediction-id)
    )
    )
)

(define-public (distribute-activity-reward (user principal) (goals-met uint) (total-goals uint))
    (let (
        (caller tx-sender)
        (user-data (unwrap! (map-get? users user) ERR_USER_NOT_FOUND))
        (current-balance (default-to u0 (map-get? token-balances user)))
        (activity-score (/ (* goals-met u100) total-goals))
    )
    (asserts! (get active user-data) ERR_NOT_AUTHORIZED)
    (asserts! (> goals-met u0) ERR_INVALID_DATA)
    (asserts! (>= total-goals goals-met) ERR_INVALID_DATA)
    
    (let (
        (base-reward (if (>= activity-score u80) DAILY_ACTIVITY_REWARD u50))
        (bonus-reward (if (is-eq goals-met total-goals) PERFECT_WEEK_BONUS u0))
        (total-reward (+ base-reward bonus-reward))
    )
    
    ;; Update user rewards
    (map-set users user (merge user-data {
        total-rewards: (+ (get total-rewards user-data) total-reward)
    }))
    
    ;; Update token balance
    (map-set token-balances user (+ current-balance total-reward))
    
    ;; Record daily activity
    (map-set daily-activities { user: user, date: block-height } {
        goals-met: goals-met,
        total-goals: total-goals,
        activity-score: activity-score,
        reward-claimed: true,
        bonus-eligible: (is-eq goals-met total-goals)
    })
    
    (ok total-reward)
    )
    )
)

(define-public (register-healthcare-provider (name (string-ascii 100)) (specialty (string-ascii 50)))
    (let (
        (caller tx-sender)
    )
    (asserts! (is-none (map-get? healthcare-providers caller)) ERR_ALREADY_EXISTS)
    
    (map-set healthcare-providers caller {
        name: name,
        specialty: specialty,
        licensed: false,
        verified-at: u0,
        access-level: u1
    })
    
    (ok caller)
    )
)

(define-public (verify-healthcare-provider (provider principal))
    (let (
        (caller tx-sender)
        (provider-data (unwrap! (map-get? healthcare-providers provider) ERR_INVALID_PROVIDER))
    )
    (asserts! (is-contract-owner) ERR_NOT_AUTHORIZED)
    
    (map-set healthcare-providers provider (merge provider-data {
        licensed: true,
        verified-at: block-height,
        access-level: u3
    }))
    
    (ok provider)
    )
)

(define-public (grant-provider-access (provider principal) (access-level uint) (duration uint))
    (let (
        (caller tx-sender)
        (user-data (unwrap! (map-get? users caller) ERR_USER_NOT_FOUND))
        (provider-data (unwrap! (map-get? healthcare-providers provider) ERR_INVALID_PROVIDER))
    )
    (asserts! (get active user-data) ERR_NOT_AUTHORIZED)
    (asserts! (get licensed provider-data) ERR_INVALID_PROVIDER)
    (asserts! (and (>= access-level u1) (<= access-level u3)) ERR_INVALID_DATA)
    
    (map-set user-permissions { user: caller, provider: provider } {
        granted: true,
        granted-at: block-height,
        access-level: access-level,
        expires-at: (+ block-height duration)
    })
    
    (ok provider)
    )
)

(define-public (revoke-provider-access (provider principal))
    (let (
        (caller tx-sender)
    )
    (map-delete user-permissions { user: caller, provider: provider })
    (ok provider)
    )
)

;; read only functions
(define-read-only (get-user-info (user principal))
    (map-get? users user)
)

(define-read-only (get-user-balance (user principal))
    (default-to u0 (map-get? token-balances user))
)

(define-read-only (get-biomarker-data (user principal) (timestamp uint))
    (map-get? biomarker-data { user: user, timestamp: timestamp })
)

(define-read-only (get-health-prediction (user principal) (prediction-id uint))
    (map-get? health-predictions { user: user, prediction-id: prediction-id })
)

(define-read-only (get-provider-info (provider principal))
    (map-get? healthcare-providers provider)
)

(define-read-only (check-provider-access (user principal) (provider principal))
    (map-get? user-permissions { user: user, provider: provider })
)

(define-read-only (get-contract-stats)
    {
        total-users: (var-get total-users),
        total-predictions: (var-get total-predictions),
        contract-balance: (var-get contract-balance),
        model-version: (var-get prediction-model-version)
    }
)
