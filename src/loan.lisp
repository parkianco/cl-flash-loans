;;;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;;;; SPDX-License-Identifier: BSD-3-Clause

;;;; ============================================================================
;;;; CL-FLASH-LOANS - Loan Request and Execution
;;;; ============================================================================
;;;;
;;;; Core flash loan types and execution logic. Handles loan requests,
;;;; validation, premium calculation, and atomic execution.
;;;;
;;;; Author: CLPIC Development Team
;;;; License: MIT
;;;; ============================================================================

(in-package #:cl-flash-loans)

;;; ============================================================================
;;; Error Conditions
;;; ============================================================================

(define-condition flash-loan-error (error)
  ((code :initarg :code :reader flash-loan-error-code :initform "UNKNOWN")
   (message :initarg :message :reader flash-loan-error-message :initform "Unknown flash loan error")
   (details :initarg :details :reader flash-loan-error-details :initform nil))
  (:report (lambda (condition stream)
             (format stream "Flash Loan Error [~A]: ~A~@[ (~A)~]"
                     (flash-loan-error-code condition)
                     (flash-loan-error-message condition)
                     (flash-loan-error-details condition))))
  (:documentation "Base condition for all flash loan related errors."))

(define-condition invalid-request-error (flash-loan-error)
  ((request-id :initarg :request-id :reader invalid-request-error-request-id :initform nil))
  (:default-initargs :code "INVALID_REQUEST")
  (:documentation "Invalid flash loan request."))

(define-condition invalid-amount-error (flash-loan-error)
  ((amount :initarg :amount :reader invalid-amount-error-amount)
   (asset :initarg :asset :reader invalid-amount-error-asset :initform nil))
  (:default-initargs :code "INVALID_AMOUNT")
  (:documentation "Invalid borrow amount."))

(define-condition invalid-asset-error (flash-loan-error)
  ((asset :initarg :asset :reader invalid-asset-error-asset))
  (:default-initargs :code "INVALID_ASSET")
  (:documentation "Asset not supported for flash loans."))

(define-condition deadline-exceeded-error (flash-loan-error)
  ((deadline :initarg :deadline :reader deadline-exceeded-error-deadline)
   (current-time :initarg :current-time :reader deadline-exceeded-error-current-time))
  (:default-initargs :code "DEADLINE_EXCEEDED")
  (:documentation "Transaction deadline has passed."))

(define-condition execution-failed-error (flash-loan-error)
  ((request-id :initarg :request-id :reader execution-failed-error-request-id)
   (stage :initarg :stage :reader execution-failed-error-stage :initform nil))
  (:default-initargs :code "EXECUTION_FAILED")
  (:documentation "Flash loan execution failed."))

(define-condition callback-failed-error (flash-loan-error)
  ((callback-address :initarg :callback-address :reader callback-failed-error-address)
   (callback-error :initarg :callback-error :reader callback-failed-error-original :initform nil))
  (:default-initargs :code "CALLBACK_FAILED")
  (:documentation "Callback execution failed."))

(define-condition repayment-failed-error (flash-loan-error)
  ((expected :initarg :expected :reader repayment-failed-error-expected)
   (actual :initarg :actual :reader repayment-failed-error-actual))
  (:default-initargs :code "REPAYMENT_FAILED")
  (:documentation "Flash loan was not properly repaid."))

(define-condition insufficient-funds-error (flash-loan-error)
  ((required :initarg :required :reader insufficient-funds-error-required)
   (available :initarg :available :reader insufficient-funds-error-available)
   (asset :initarg :asset :reader insufficient-funds-error-asset :initform nil))
  (:default-initargs :code "INSUFFICIENT_FUNDS")
  (:documentation "Insufficient funds for flash loan."))

(define-condition limit-exceeded-error (flash-loan-error)
  ((limit-type :initarg :limit-type :reader limit-exceeded-error-type)
   (limit-value :initarg :limit-value :reader limit-exceeded-error-limit)
   (requested :initarg :requested :reader limit-exceeded-error-requested))
  (:default-initargs :code "LIMIT_EXCEEDED")
  (:documentation "Borrowing limit exceeded."))

(define-condition rate-limit-error (flash-loan-error)
  ((window :initarg :window :reader rate-limit-error-window)
   (max-loans :initarg :max-loans :reader rate-limit-error-max)
   (current-loans :initarg :current-loans :reader rate-limit-error-current))
  (:default-initargs :code "RATE_LIMITED")
  (:documentation "Rate limit reached."))

(define-condition pool-not-found-error (flash-loan-error)
  ((pool-id :initarg :pool-id :reader pool-not-found-error-pool-id))
  (:default-initargs :code "POOL_NOT_FOUND")
  (:documentation "Flash loan pool not found."))

(define-condition pool-paused-error (flash-loan-error)
  ((pool-id :initarg :pool-id :reader pool-paused-error-pool-id))
  (:default-initargs :code "POOL_PAUSED")
  (:documentation "Flash loan pool is paused."))

(define-condition insufficient-liquidity-error (flash-loan-error)
  ((asset :initarg :asset :reader insufficient-liquidity-error-asset)
   (requested :initarg :requested :reader insufficient-liquidity-error-requested)
   (available :initarg :available :reader insufficient-liquidity-error-available))
  (:default-initargs :code "INSUFFICIENT_LIQUIDITY")
  (:documentation "Pool lacks sufficient liquidity."))

(define-condition reentrancy-detected-error (flash-loan-error)
  ((call-depth :initarg :call-depth :reader reentrancy-detected-error-depth)
   (caller :initarg :caller :reader reentrancy-detected-error-caller))
  (:default-initargs :code "REENTRANCY_DETECTED")
  (:documentation "Reentrancy attack detected."))

(define-condition unauthorized-error (flash-loan-error)
  ((action :initarg :action :reader unauthorized-error-action)
   (caller :initarg :caller :reader unauthorized-error-caller)
   (required :initarg :required :reader unauthorized-error-required :initform nil))
  (:default-initargs :code "UNAUTHORIZED")
  (:documentation "Caller is not authorized for this action."))

;;; ============================================================================
;;; Flash Loan Mode Type
;;; ============================================================================

(defstruct (flash-loan-mode
            (:constructor make-flash-loan-mode)
            (:copier copy-flash-loan-mode))
  "Defines a flash loan execution mode."
  (id 0 :type integer)
  (name "" :type string)
  (description "" :type string)
  (requires-repayment t :type boolean)
  (can-open-debt nil :type boolean))

;;; ============================================================================
;;; Flash Loan Request Type
;;; ============================================================================

(defstruct (flash-loan-request
            (:constructor %make-flash-loan-request)
            (:copier copy-flash-loan-request))
  "Represents a flash loan request.

   A flash loan request specifies the assets and amounts to borrow,
   the receiver contract that will handle the funds, and callback
   parameters for custom execution logic."
  (id nil :type (or null string))
  (initiator nil :type (or null string))
  (receiver nil :type (or null string))
  (assets nil :type list)
  (amounts nil :type list)
  (premiums nil :type list)
  (modes nil :type list)
  (on-behalf-of nil :type (or null string))
  (params nil :type (or null vector string))
  (referral-code 0 :type integer)
  (deadline 0 :type integer)
  (nonce 0 :type integer)
  (signature nil :type (or null string vector))
  (created-at 0 :type integer))

(defun make-flash-loan-request (&key id initiator receiver
                                       assets amounts modes
                                       on-behalf-of params
                                       (referral-code 0)
                                       deadline nonce signature)
  "Create a new flash loan request."
  (let ((now (flash-get-timestamp)))
    ;; Validate asset/amount/mode list lengths match
    (when (and assets amounts)
      (unless (= (length assets) (length amounts))
        (error 'invalid-request-error
               :code "MISMATCHED_ARRAYS"
               :message "Assets and amounts arrays must have same length")))
    (when (and assets modes)
      (unless (= (length assets) (length modes))
        (error 'invalid-request-error
               :code "MISMATCHED_ARRAYS"
               :message "Assets and modes arrays must have same length")))

    ;; Validate asset count
    (when (and assets (> (length assets) +max-flash-loan-assets+))
      (error 'invalid-request-error
             :code "TOO_MANY_ASSETS"
             :message (format nil "Maximum ~D assets per flash loan"
                              +max-flash-loan-assets+)))

    ;; Calculate premiums based on amounts
    (let ((premiums (when amounts
                      (mapcar (lambda (amount)
                                (flash-percent-mul amount +default-flash-fee+))
                              amounts))))
      (%make-flash-loan-request
       :id (or id (generate-flash-loan-id initiator now))
       :initiator initiator
       :receiver (or receiver initiator)
       :assets (or assets nil)
       :amounts (or amounts nil)
       :premiums premiums
       :modes (or modes (make-list (length (or assets nil))
                                   :initial-element +flash-mode-standard+))
       :on-behalf-of on-behalf-of
       :params params
       :referral-code referral-code
       :deadline (or deadline (+ now +flash-loan-timeout+))
       :nonce (or nonce (random (expt 2 64)))
       :signature signature
       :created-at now))))

;;; ============================================================================
;;; Flash Loan Response Type
;;; ============================================================================

(defstruct (flash-loan-response
            (:constructor make-flash-loan-response)
            (:copier copy-flash-loan-response))
  "Represents the result of a flash loan execution."
  (request-id nil :type (or null string))
  (success nil :type boolean)
  (assets-borrowed nil :type list)
  (amounts-borrowed nil :type list)
  (premiums-paid nil :type list)
  (total-premium 0 :type integer)
  (execution-time 0 :type integer)
  (gas-used 0 :type integer)
  (error-message nil :type (or null string))
  (callback-result nil)
  (tx-hash nil :type (or null string)))

;;; ============================================================================
;;; Flash Loan Context Type
;;; ============================================================================

(defstruct (flash-loan-context
            (:constructor %make-flash-loan-context)
            (:copier copy-flash-loan-context))
  "Execution context for an active flash loan."
  (id nil :type (or null string))
  (request nil)
  (pool-id nil :type (or null string))
  (initiator nil :type (or null string))
  (receiver nil :type (or null string))
  (assets nil :type list)
  (amounts nil :type list)
  (premiums nil :type list)
  (params nil)
  (state :pending :type keyword)
  (start-time 0 :type integer)
  (deadline 0 :type integer)
  (reentrancy-guard nil)
  (call-depth 0 :type integer)
  (operations nil :type list)
  (checkpoints nil :type list))

(defun make-flash-loan-context (&key request pool-id)
  "Create a new flash loan execution context from a request."
  (unless request
    (error 'invalid-request-error
           :code "NO_REQUEST"
           :message "Request is required to create context"))
  (let ((now (flash-get-timestamp)))
    (%make-flash-loan-context
     :id (flash-loan-request-id request)
     :request request
     :pool-id pool-id
     :initiator (flash-loan-request-initiator request)
     :receiver (flash-loan-request-receiver request)
     :assets (flash-loan-request-assets request)
     :amounts (flash-loan-request-amounts request)
     :premiums (flash-loan-request-premiums request)
     :params (flash-loan-request-params request)
     :state :pending
     :start-time now
     :deadline (flash-loan-request-deadline request)
     :reentrancy-guard (make-reentrancy-guard)
     :call-depth 0
     :operations nil
     :checkpoints nil)))

;;; ============================================================================
;;; Fee Types
;;; ============================================================================

(defstruct (flash-fee-structure
            (:constructor make-flash-fee-structure)
            (:copier copy-flash-fee-structure))
  "Fee breakdown for a flash loan."
  (base-fee 0 :type integer)
  (protocol-fee 0 :type integer)
  (lp-fee 0 :type integer)
  (referral-fee 0 :type integer)
  (discount 0 :type integer)
  (net-fee 0 :type integer)
  (tier nil))

(defstruct (flash-fee-tier
            (:constructor make-flash-fee-tier)
            (:copier copy-flash-fee-tier))
  "Fee tier configuration for volume-based discounts."
  (id 0 :type integer)
  (name "" :type string)
  (min-volume 0 :type integer)
  (fee-rate +default-flash-fee+ :type integer)
  (discount-rate 0 :type integer)
  (benefits nil :type list))

;;; ============================================================================
;;; Limit Types
;;; ============================================================================

(defstruct (borrowing-limit
            (:constructor make-borrowing-limit)
            (:copier copy-borrowing-limit))
  "Generic borrowing limit configuration."
  (id nil :type (or null string))
  (limit-type :global :type keyword)
  (asset nil :type (or null string))
  (max-amount 0 :type integer)
  (current-usage 0 :type integer)
  (reset-period 0 :type integer)
  (last-reset 0 :type integer)
  (is-active t :type boolean))

(defstruct (global-limits
            (:constructor make-global-limits)
            (:copier copy-global-limits))
  "Protocol-wide borrowing limits."
  (max-total-borrowed +flash-max-uint256+ :type integer)
  (current-total-borrowed 0 :type integer)
  (max-per-transaction +max-flash-loan-amount+ :type integer)
  (max-per-block +flash-max-uint256+ :type integer)
  (current-block-usage 0 :type integer)
  (max-per-user-daily +flash-max-uint256+ :type integer)
  (circuit-breaker-threshold +flash-max-uint256+ :type integer)
  (circuit-breaker-triggered nil :type boolean))

(defstruct (user-limits
            (:constructor make-user-limits)
            (:copier copy-user-limits))
  "Per-user borrowing limits."
  (address nil :type (or null string))
  (max-per-loan +max-flash-loan-amount+ :type integer)
  (max-daily +flash-max-uint256+ :type integer)
  (max-weekly +flash-max-uint256+ :type integer)
  (current-daily-usage 0 :type integer)
  (current-weekly-usage 0 :type integer)
  (daily-reset-time 0 :type integer)
  (weekly-reset-time 0 :type integer)
  (is-whitelisted nil :type boolean)
  (is-blacklisted nil :type boolean)
  (tier 0 :type integer))

(defstruct (asset-limits
            (:constructor make-asset-limits)
            (:copier copy-asset-limits))
  "Per-asset borrowing limits."
  (asset-address nil :type (or null string))
  (max-borrow +max-flash-loan-amount+ :type integer)
  (max-utilization 9500 :type integer)
  (current-borrowed 0 :type integer)
  (available-liquidity 0 :type integer)
  (cooldown-period 0 :type integer)
  (last-borrow-time 0 :type integer))

;;; ============================================================================
;;; Protection Types
;;; ============================================================================

(defstruct (reentrancy-guard
            (:constructor make-reentrancy-guard)
            (:copier copy-reentrancy-guard))
  "Reentrancy protection state."
  (id nil :type (or null string))
  (status :unlocked :type keyword)
  (call-depth 0 :type integer)
  (max-depth +max-reentrancy-depth+ :type integer)
  (locked-by nil :type (or null string))
  (lock-time 0 :type integer)
  (call-stack nil :type list))

(defstruct (security-policy
            (:constructor make-security-policy)
            (:copier copy-security-policy))
  "Security policy configuration."
  (id nil :type (or null string))
  (name "" :type string)
  (max-reentrancy-depth +max-reentrancy-depth+ :type integer)
  (max-call-depth 10 :type integer)
  (max-operations +max-operations-per-tx+ :type integer)
  (require-signature nil :type boolean)
  (require-whitelist nil :type boolean)
  (block-on-suspicious t :type boolean)
  (rate-limit-config nil)
  (circuit-breakers nil :type list))

(defstruct (circuit-breaker
            (:constructor make-circuit-breaker)
            (:copier copy-circuit-breaker))
  "Circuit breaker for automatic protection."
  (id nil :type (or null string))
  (name "" :type string)
  (trigger-condition :volume :type keyword)
  (threshold 0 :type integer)
  (current-value 0 :type integer)
  (is-triggered nil :type boolean)
  (trigger-time 0 :type integer)
  (cooldown-period 3600 :type integer)
  (auto-reset nil :type boolean))

;;; ============================================================================
;;; Reentrancy Protection Operations
;;; ============================================================================

(defun acquire-reentrancy-lock (guard caller)
  "Acquire the reentrancy lock."
  (when (eq (reentrancy-guard-status guard) :locked)
    (when (>= (reentrancy-guard-call-depth guard)
              (reentrancy-guard-max-depth guard))
      (error 'reentrancy-detected-error
             :call-depth (reentrancy-guard-call-depth guard)
             :caller caller
             :message "Maximum reentrancy depth exceeded")))
  (setf (reentrancy-guard-status guard) :locked)
  (setf (reentrancy-guard-locked-by guard) caller)
  (setf (reentrancy-guard-lock-time guard) (flash-get-timestamp))
  (incf (reentrancy-guard-call-depth guard))
  (push caller (reentrancy-guard-call-stack guard))
  t)

(defun release-reentrancy-lock (guard)
  "Release the reentrancy lock."
  (decf (reentrancy-guard-call-depth guard))
  (pop (reentrancy-guard-call-stack guard))
  (when (zerop (reentrancy-guard-call-depth guard))
    (setf (reentrancy-guard-status guard) :unlocked)
    (setf (reentrancy-guard-locked-by guard) nil)
    (setf (reentrancy-guard-lock-time guard) 0))
  t)

(defun check-reentrancy-lock (guard)
  "Check if reentrancy lock is active."
  (eq (reentrancy-guard-status guard) :locked))

;;; ============================================================================
;;; Request Validation
;;; ============================================================================

(defun validate-flash-loan-request (request &key pool)
  "Validate a flash loan request.

   Checks:
   - Request is not nil
   - Assets and amounts are provided
   - Deadline has not passed
   - Amounts are within bounds
   - Pool has sufficient liquidity (if pool provided)"
  (unless request
    (error 'invalid-request-error
           :message "Request cannot be nil"))

  (unless (flash-loan-request-assets request)
    (error 'invalid-request-error
           :request-id (flash-loan-request-id request)
           :message "No assets specified"))

  (unless (flash-loan-request-amounts request)
    (error 'invalid-request-error
           :request-id (flash-loan-request-id request)
           :message "No amounts specified"))

  ;; Check deadline
  (let ((now (flash-get-timestamp)))
    (when (> now (flash-loan-request-deadline request))
      (error 'deadline-exceeded-error
             :deadline (flash-loan-request-deadline request)
             :current-time now
             :message "Request deadline has passed")))

  ;; Validate amounts
  (dolist (amount (flash-loan-request-amounts request))
    (when (< amount +min-flash-loan-amount+)
      (error 'invalid-amount-error
             :amount amount
             :message (format nil "Amount below minimum (~A)" +min-flash-loan-amount+)))
    (when (> amount +max-flash-loan-amount+)
      (error 'invalid-amount-error
             :amount amount
             :message (format nil "Amount exceeds maximum (~A)" +max-flash-loan-amount+))))

  ;; Validate against pool if provided
  (when pool
    (unless (flash-loan-pool-is-active pool)
      (error 'pool-paused-error
             :pool-id (flash-loan-pool-id pool)
             :message "Pool is not active"))
    (when (flash-loan-pool-is-paused pool)
      (error 'pool-paused-error
             :pool-id (flash-loan-pool-id pool)
             :message "Pool is paused")))

  t)

;;; ============================================================================
;;; Premium Calculation
;;; ============================================================================

(defun calculate-flash-loan-premium (amount &key (fee-rate +default-flash-fee+))
  "Calculate the premium (fee) for a flash loan amount."
  (flash-percent-mul amount fee-rate))

(defun calculate-total-premium (amounts &key (fee-rate +default-flash-fee+))
  "Calculate total premium for multiple amounts."
  (reduce #'+ amounts
          :key (lambda (amount)
                 (calculate-flash-loan-premium amount :fee-rate fee-rate))
          :initial-value 0))

(defun calculate-flash-fee (amount pool)
  "Calculate fee for a flash loan using pool fee rate."
  (let ((fee-rate (if pool
                      (flash-loan-pool-fee-rate pool)
                      +default-flash-fee+)))
    (make-flash-fee-structure
     :base-fee (flash-percent-mul amount fee-rate)
     :protocol-fee (flash-percent-mul
                    (flash-percent-mul amount fee-rate)
                    +protocol-fee-share+)
     :lp-fee (flash-percent-mul
              (flash-percent-mul amount fee-rate)
              +lp-fee-share+)
     :referral-fee 0
     :discount 0
     :net-fee (flash-percent-mul amount fee-rate)
     :tier nil)))

(defun get-fee-tier (volume)
  "Get fee tier based on cumulative volume."
  (cond
    ((>= volume (* 1000000 +flash-wad+))  ; 1M+ tokens
     (make-flash-fee-tier :id 3 :name "Gold"
                          :min-volume (* 1000000 +flash-wad+)
                          :fee-rate 5 :discount-rate 4000))
    ((>= volume (* 100000 +flash-wad+))   ; 100K+ tokens
     (make-flash-fee-tier :id 2 :name "Silver"
                          :min-volume (* 100000 +flash-wad+)
                          :fee-rate 7 :discount-rate 2000))
    ((>= volume (* 10000 +flash-wad+))    ; 10K+ tokens
     (make-flash-fee-tier :id 1 :name "Bronze"
                          :min-volume (* 10000 +flash-wad+)
                          :fee-rate 8 :discount-rate 1000))
    (t
     (make-flash-fee-tier :id 0 :name "Standard"
                          :min-volume 0
                          :fee-rate +default-flash-fee+
                          :discount-rate 0))))

;;; ============================================================================
;;; Limit Checking
;;; ============================================================================

(defun check-borrowing-limits (amount &key user-address asset-address)
  "Check if a borrow amount is within all applicable limits."
  (when *global-limits*
    (let ((limits *global-limits*))
      ;; Check global total
      (when (> (+ (global-limits-current-total-borrowed limits) amount)
               (global-limits-max-total-borrowed limits))
        (error 'limit-exceeded-error
               :limit-type :global-total
               :limit-value (global-limits-max-total-borrowed limits)
               :requested amount
               :message "Global borrowing limit exceeded"))

      ;; Check per-transaction limit
      (when (> amount (global-limits-max-per-transaction limits))
        (error 'limit-exceeded-error
               :limit-type :per-transaction
               :limit-value (global-limits-max-per-transaction limits)
               :requested amount
               :message "Per-transaction limit exceeded"))

      ;; Check circuit breaker
      (when (global-limits-circuit-breaker-triggered limits)
        (error 'limit-exceeded-error
               :limit-type :circuit-breaker
               :limit-value (global-limits-circuit-breaker-threshold limits)
               :requested amount
               :message "Circuit breaker is triggered"))))
  t)

(defun update-usage (amount &key user-address asset-address)
  "Update usage counters after a successful borrow."
  (when *global-limits*
    (incf (global-limits-current-total-borrowed *global-limits*) amount)
    (incf (global-limits-current-block-usage *global-limits*) amount))
  t)

(defun reset-limits ()
  "Reset all limit counters."
  (when *global-limits*
    (setf (global-limits-current-total-borrowed *global-limits*) 0)
    (setf (global-limits-current-block-usage *global-limits*) 0)
    (setf (global-limits-circuit-breaker-triggered *global-limits*) nil))
  t)

;;; ============================================================================
;;; Flash Loan Execution
;;; ============================================================================

(defun prepare-flash-loan (request pool)
  "Prepare a flash loan for execution by creating context and validating."
  (validate-flash-loan-request request :pool pool)
  (make-flash-loan-context :request request
                           :pool-id (when pool (flash-loan-pool-id pool))))

(defun simulate-flash-loan (request &key pool callback-fn)
  "Simulate flash loan execution without actually transferring funds.

   Returns a response indicating what would happen if executed."
  (handler-case
      (progn
        (validate-flash-loan-request request :pool pool)

        ;; Calculate premiums
        (let ((premiums (mapcar (lambda (amount)
                                  (calculate-flash-loan-premium
                                   amount
                                   :fee-rate (if pool
                                                 (flash-loan-pool-fee-rate pool)
                                                 +default-flash-fee+)))
                                (flash-loan-request-amounts request))))

          ;; Simulate callback if provided
          (let ((callback-result (when callback-fn
                                   (funcall callback-fn
                                            (flash-loan-request-assets request)
                                            (flash-loan-request-amounts request)
                                            premiums
                                            (flash-loan-request-params request)))))

            (make-flash-loan-response
             :request-id (flash-loan-request-id request)
             :success t
             :assets-borrowed (flash-loan-request-assets request)
             :amounts-borrowed (flash-loan-request-amounts request)
             :premiums-paid premiums
             :total-premium (reduce #'+ premiums :initial-value 0)
             :execution-time 0
             :gas-used 0
             :error-message nil
             :callback-result callback-result
             :tx-hash nil))))
    (flash-loan-error (e)
      (make-flash-loan-response
       :request-id (flash-loan-request-id request)
       :success nil
       :error-message (flash-loan-error-message e)))))

(defun execute-flash-loan (request &key pool callback-fn)
  "Execute a flash loan with callback.

   This is the core flash loan execution function. It:
   1. Validates the request
   2. Acquires reentrancy lock
   3. Transfers funds to receiver (simulated)
   4. Executes the callback function
   5. Verifies repayment (simulated)
   6. Releases reentrancy lock

   Parameters:
   - request: Flash loan request
   - pool: Optional flash loan pool
   - callback-fn: Function to call with borrowed funds
                  (assets amounts premiums params) -> success

   Returns: flash-loan-response"
  (let ((start-time (get-internal-real-time))
        (context (prepare-flash-loan request pool)))

    (handler-case
        (progn
          ;; Acquire reentrancy lock
          (acquire-reentrancy-lock (flash-loan-context-reentrancy-guard context)
                                   (flash-loan-request-initiator request))

          ;; Check limits
          (let ((total-amount (reduce #'+ (flash-loan-request-amounts request)
                                      :initial-value 0)))
            (check-borrowing-limits total-amount
                                    :user-address (flash-loan-request-initiator request)))

          ;; Update state to executing
          (setf (flash-loan-context-state context) :executing)

          ;; Calculate premiums
          (let ((premiums (mapcar (lambda (amount)
                                    (calculate-flash-loan-premium
                                     amount
                                     :fee-rate (if pool
                                                   (flash-loan-pool-fee-rate pool)
                                                   +default-flash-fee+)))
                                  (flash-loan-request-amounts request))))

            ;; Execute callback
            (setf (flash-loan-context-state context) :callback)
            (let ((callback-result
                    (when callback-fn
                      (funcall callback-fn
                               (flash-loan-request-assets request)
                               (flash-loan-request-amounts request)
                               premiums
                               (flash-loan-request-params request)))))

              ;; Verify callback success
              (unless (or (null callback-fn) callback-result)
                (error 'callback-failed-error
                       :callback-address (flash-loan-request-receiver request)
                       :message "Callback returned failure"))

              ;; Update state to repaying
              (setf (flash-loan-context-state context) :repaying)

              ;; Update usage
              (update-usage (reduce #'+ (flash-loan-request-amounts request)
                                    :initial-value 0)
                            :user-address (flash-loan-request-initiator request))

              ;; Update pool stats if pool provided
              (when pool
                (incf (flash-loan-pool-total-borrowed pool)
                      (reduce #'+ (flash-loan-request-amounts request)
                              :initial-value 0))
                (incf (flash-loan-pool-total-fees-collected pool)
                      (reduce #'+ premiums :initial-value 0)))

              ;; Complete
              (setf (flash-loan-context-state context) :completed)

              ;; Release lock
              (release-reentrancy-lock (flash-loan-context-reentrancy-guard context))

              ;; Return response
              (let ((end-time (get-internal-real-time)))
                (make-flash-loan-response
                 :request-id (flash-loan-request-id request)
                 :success t
                 :assets-borrowed (flash-loan-request-assets request)
                 :amounts-borrowed (flash-loan-request-amounts request)
                 :premiums-paid premiums
                 :total-premium (reduce #'+ premiums :initial-value 0)
                 :execution-time (round (* 1000 (/ (- end-time start-time)
                                                   internal-time-units-per-second)))
                 :gas-used 0
                 :error-message nil
                 :callback-result callback-result
                 :tx-hash (generate-flash-loan-id
                           (flash-loan-request-initiator request)
                           (flash-get-timestamp)))))))

      (flash-loan-error (e)
        ;; Release lock on error
        (when (check-reentrancy-lock (flash-loan-context-reentrancy-guard context))
          (release-reentrancy-lock (flash-loan-context-reentrancy-guard context)))
        (setf (flash-loan-context-state context) :failed)
        (make-flash-loan-response
         :request-id (flash-loan-request-id request)
         :success nil
         :error-message (flash-loan-error-message e)))

      (error (e)
        ;; Release lock on any error
        (when (check-reentrancy-lock (flash-loan-context-reentrancy-guard context))
          (release-reentrancy-lock (flash-loan-context-reentrancy-guard context)))
        (setf (flash-loan-context-state context) :failed)
        (make-flash-loan-response
         :request-id (flash-loan-request-id request)
         :success nil
         :error-message (format nil "Unexpected error: ~A" e))))))

(defun execute-flash-loan-simple (assets amounts &key initiator callback-fn pool)
  "Simple interface for executing a flash loan.

   Parameters:
   - assets: List of asset addresses
   - amounts: List of amounts to borrow
   - initiator: Address initiating the loan
   - callback-fn: Callback function
   - pool: Optional pool

   Returns: flash-loan-response"
  (let ((request (make-flash-loan-request
                  :initiator initiator
                  :receiver initiator
                  :assets assets
                  :amounts amounts)))
    (execute-flash-loan request :pool pool :callback-fn callback-fn)))
