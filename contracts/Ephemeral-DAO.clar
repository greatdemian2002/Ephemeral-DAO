;; Ephemeral DAO Contract
;; A DAO that auto-dissolves after achieving one specific goal

;; Constants
(define-constant ERR_NOT_MEMBER (err u100))
(define-constant ERR_ALREADY_MEMBER (err u101))
(define-constant ERR_DAO_DISSOLVED (err u102))
(define-constant ERR_GOAL_NOT_ACHIEVED (err u103))
(define-constant ERR_INSUFFICIENT_VOTES (err u104))
(define-constant ERR_ALREADY_VOTED (err u105))
(define-constant CONTRACT_OWNER tx-sender)

;; Data Variables
(define-data-var dao-name (string-ascii 64) "")
(define-data-var dao-goal (string-ascii 256) "")
(define-data-var is-dissolved bool false)
(define-data-var total-members uint u0)
(define-data-var goal-achieved bool false)
(define-data-var dissolution-height uint u0)
(define-data-var goal-vote-count uint u0)
(define-data-var dissolution-vote-count uint u0)

;; Data Maps
(define-map members principal bool)
(define-map goal-votes principal bool)
(define-map dissolution-votes principal bool)

;; Read-only functions
(define-read-only (get-dao-info)
  {
    name: (var-get dao-name),
    goal: (var-get dao-goal),
    is-dissolved: (var-get is-dissolved),
    total-members: (var-get total-members),
    goal-achieved: (var-get goal-achieved),
    dissolution-height: (var-get dissolution-height)
  }
)

(define-read-only (is-member (member principal))
  (default-to false (map-get? members member))
)

(define-read-only (has-voted-goal (member principal))
  (default-to false (map-get? goal-votes member))
)

(define-read-only (has-voted-dissolution (member principal))
  (default-to false (map-get? dissolution-votes member))
)

(define-read-only (get-goal-vote-count)
  (var-get goal-vote-count)
)

(define-read-only (get-dissolution-vote-count)
  (var-get dissolution-vote-count)
)


;; Private functions
(define-private (check-dao-active)
  (ok (asserts! (not (var-get is-dissolved)) ERR_DAO_DISSOLVED))
)

(define-private (check-member (member principal))
  (ok (asserts! (is-member member) ERR_NOT_MEMBER))
)

;; Public functions

;; Initialize the DAO
(define-public (initialize-dao (name (string-ascii 64)) (goal (string-ascii 256)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) (err u403))
    (asserts! (is-eq (var-get dao-name) "") (err u400))
    (asserts! (> (len name) u0) (err u401))
    (asserts! (> (len goal) u0) (err u402))
    (var-set dao-name name)
    (var-set dao-goal goal)
    (map-set members tx-sender true)
    (var-set total-members u1)
    (ok true)
  )
)

;; Join the DAO
(define-public (join-dao)
  (begin
    (try! (check-dao-active))
    (asserts! (not (is-member tx-sender)) ERR_ALREADY_MEMBER)
    (map-set members tx-sender true)
    (var-set total-members (+ (var-get total-members) u1))
    (ok true)
  )
)

;; Vote that the goal has been achieved
(define-public (vote-goal-achieved)
  (begin
    (try! (check-dao-active))
    (try! (check-member tx-sender))
    (asserts! (not (has-voted-goal tx-sender)) ERR_ALREADY_VOTED)
    (map-set goal-votes tx-sender true)
    (var-set goal-vote-count (+ (var-get goal-vote-count) u1))

    ;; Check if majority has voted for goal achievement
    (let ((vote-count (var-get goal-vote-count))
          (majority-threshold (/ (+ (var-get total-members) u1) u2)))
      (if (>= vote-count majority-threshold)
        (begin
          (var-set goal-achieved true)
          (try! (auto-dissolve))
          (ok true)
        )
        (ok true)
      )
    )
  )
)

;; Auto-dissolve the DAO when goal is achieved
(define-private (auto-dissolve)
  (begin
    (asserts! (var-get goal-achieved) ERR_GOAL_NOT_ACHIEVED)
    (var-set is-dissolved true)
    (var-set dissolution-height block-height)
    (ok true)
  )
)

;; Emergency dissolution vote (requires unanimous consent)
(define-public (vote-dissolve)
  (begin
    (try! (check-dao-active))
    (try! (check-member tx-sender))
    (asserts! (not (has-voted-dissolution tx-sender)) ERR_ALREADY_VOTED)
    (map-set dissolution-votes tx-sender true)
    (var-set dissolution-vote-count (+ (var-get dissolution-vote-count) u1))

    ;; Check if all members have voted for dissolution
    (let ((vote-count (var-get dissolution-vote-count)))
      (if (is-eq vote-count (var-get total-members))
        (begin
          (var-set is-dissolved true)
          (var-set dissolution-height block-height)
          (ok true)
        )
        (ok true)
      )
    )
  )
)

;; Leave the DAO (only if not dissolved)
(define-public (leave-dao)
  (begin
    (try! (check-dao-active))
    (try! (check-member tx-sender))

    ;; Adjust vote counts if member had voted
    (if (has-voted-goal tx-sender)
      (var-set goal-vote-count (- (var-get goal-vote-count) u1))
      true)
    (if (has-voted-dissolution tx-sender)
      (var-set dissolution-vote-count (- (var-get dissolution-vote-count) u1))
      true)

    (map-delete members tx-sender)
    (map-delete goal-votes tx-sender)
    (map-delete dissolution-votes tx-sender)
    (var-set total-members (- (var-get total-members) u1))
    (ok true)
  )
)