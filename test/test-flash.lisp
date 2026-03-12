;;;; ============================================================================
;;;; CL-FLASH-LOANS - Test Suite
;;;; ============================================================================
;;;;
;;;; Tests for the flash loan protocol implementation.
;;;;
;;;; Author: CLPIC Development Team
;;;; License: MIT
;;;; ============================================================================

(in-package #:cl-flash-loans.test)

;;; ============================================================================
;;; Test Framework (minimal built-in)
;;; ============================================================================

(defvar *test-results* nil)
(defvar *current-test* nil)

(defmacro deftest (name &body body)
  "Define a test case."
  `(defun ,name ()
     (let ((*current-test* ',name))
       (handler-case
           (progn ,@body
                  (push (cons ',name :pass) *test-results*)
                  t)
         (error (e)
           (push (cons ',name (format nil "FAIL: ~A" e)) *test-results*)
           nil)))))

(defun assert-true (value &optional message)
  "Assert that value is true."
  (unless value
    (error "Assertion failed~@[: ~A~]" message)))

(defun assert-false (value &optional message)
  "Assert that value is false."
  (when value
    (error "Assertion failed (expected false)~@[: ~A~]" message)))

(defun assert-equal (expected actual &optional message)
  "Assert that expected equals actual."
  (unless (equal expected actual)
    (error "Assertion failed: expected ~S, got ~S~@[: ~A~]"
           expected actual message)))

(defun assert-error (thunk &optional error-type message)
  "Assert that thunk signals an error."
  (let ((signaled nil))
    (handler-case (funcall thunk)
      (error (e)
        (setf signaled t)
        (when (and error-type (not (typep e error-type)))
          (error "Wrong error type: expected ~A, got ~A~@[: ~A~]"
                 error-type (type-of e) message))))
    (unless signaled
      (error "Expected error not signaled~@[: ~A~]" message))))

;;; ============================================================================
;;; Utility Tests
;;; ============================================================================

(deftest test-flash-wad-mul
  "Test WAD multiplication."
  (assert-equal 0 (cl-flash-loans:flash-wad-mul 0 1000000000000000000))
  (assert-equal 1000000000000000000
                (cl-flash-loans:flash-wad-mul
                 1000000000000000000
                 1000000000000000000))
  (assert-equal 2000000000000000000
                (cl-flash-loans:flash-wad-mul
                 2000000000000000000
                 1000000000000000000)))

(deftest test-flash-wad-div
  "Test WAD division."
  (assert-equal 1000000000000000000
                (cl-flash-loans:flash-wad-div
                 1000000000000000000
                 1000000000000000000))
  (assert-error (lambda () (cl-flash-loans:flash-wad-div 1 0))
                'division-by-zero))

(deftest test-flash-percent-mul
  "Test percentage multiplication."
  (assert-equal 0 (cl-flash-loans:flash-percent-mul 0 5000))
  (assert-equal 500 (cl-flash-loans:flash-percent-mul 1000 5000))
  (assert-equal 9 (cl-flash-loans:flash-percent-mul 10000 9))) ; 0.09%

(deftest test-flash-get-timestamp
  "Test timestamp generation."
  (let ((ts (cl-flash-loans:flash-get-timestamp)))
    (assert-true (> ts 0) "Timestamp should be positive")
    (assert-true (< ts (expt 2 40)) "Timestamp should be reasonable")))

;;; ============================================================================
;;; Pool Tests
;;; ============================================================================

(deftest test-create-pool
  "Test pool creation."
  (cl-flash-loans:clear-flash-registries)
  (let ((pool (cl-flash-loans:create-flash-pool
               :name "Test Pool"
               :protocol "TEST"
               :fee-rate 10)))
    (assert-true pool "Pool should be created")
    (assert-equal "Test Pool" (cl-flash-loans:flash-loan-pool-name pool))
    (assert-equal "TEST" (cl-flash-loans:flash-loan-pool-protocol pool))
    (assert-equal 10 (cl-flash-loans:flash-loan-pool-fee-rate pool))
    (assert-true (cl-flash-loans:flash-loan-pool-is-active pool))))

(deftest test-pool-registry
  "Test pool registry operations."
  (cl-flash-loans:clear-flash-registries)
  (let ((pool (cl-flash-loans:create-flash-pool :name "Registry Test")))
    (let ((retrieved (cl-flash-loans:get-flash-pool
                      (cl-flash-loans:flash-loan-pool-id pool))))
      (assert-equal pool retrieved "Should retrieve same pool"))))

(deftest test-add-pool-asset
  "Test adding assets to pool."
  (cl-flash-loans:clear-flash-registries)
  (let ((pool (cl-flash-loans:create-flash-pool :name "Asset Test")))
    (let ((asset (cl-flash-loans:add-pool-asset
                  pool "0xTOKEN"
                  :symbol "TKN"
                  :decimals 18
                  :liquidity 1000000)))
      (assert-true asset "Asset should be created")
      (assert-equal "0xTOKEN" (cl-flash-loans:flash-pool-asset-address asset))
      (assert-equal "TKN" (cl-flash-loans:flash-pool-asset-symbol asset))
      (assert-equal 1000000 (cl-flash-loans:flash-pool-asset-available-liquidity asset))
      (assert-equal 1000000 (cl-flash-loans:flash-loan-pool-reserves pool)))))

(deftest test-pool-liquidity
  "Test liquidity management."
  (cl-flash-loans:clear-flash-registries)
  (let ((pool (cl-flash-loans:create-flash-pool :name "Liquidity Test")))
    (cl-flash-loans:add-pool-asset pool "0xA" :liquidity 1000)
    (assert-equal 1000 (cl-flash-loans:get-pool-liquidity pool))
    (assert-equal 1000 (cl-flash-loans:get-pool-liquidity pool "0xA"))

    (cl-flash-loans:add-liquidity pool "0xA" 500)
    (assert-equal 1500 (cl-flash-loans:get-pool-liquidity pool "0xA"))

    (cl-flash-loans:remove-liquidity pool "0xA" 200)
    (assert-equal 1300 (cl-flash-loans:get-pool-liquidity pool "0xA"))))

(deftest test-pool-pause
  "Test pool pause/unpause."
  (cl-flash-loans:clear-flash-registries)
  (let ((pool (cl-flash-loans:create-flash-pool :name "Pause Test")))
    (assert-false (cl-flash-loans:flash-loan-pool-is-paused pool))
    (cl-flash-loans:pause-flash-pool pool)
    (assert-true (cl-flash-loans:flash-loan-pool-is-paused pool))
    (cl-flash-loans:unpause-flash-pool pool)
    (assert-false (cl-flash-loans:flash-loan-pool-is-paused pool))))

;;; ============================================================================
;;; Callback Tests
;;; ============================================================================

(deftest test-register-callback
  "Test callback registration."
  (cl-flash-loans:clear-flash-registries)
  (let ((entry (cl-flash-loans:register-callback
                "0xCALLBACK"
                :name "Test Callback"
                :trusted t)))
    (assert-true entry "Entry should be created")
    (assert-equal "0xCALLBACK"
                  (cl-flash-loans:callback-registry-entry-address entry))
    (assert-true (cl-flash-loans:callback-registry-entry-is-trusted entry))))

(deftest test-callback-lookup
  "Test callback lookup."
  (cl-flash-loans:clear-flash-registries)
  (cl-flash-loans:register-callback "0xCB1" :name "CB1")
  (cl-flash-loans:register-callback "0xCB2" :name "CB2")

  (let ((cb1 (cl-flash-loans:get-callback "0xCB1")))
    (assert-true cb1 "Should find CB1")
    (assert-equal "CB1" (cl-flash-loans:callback-registry-entry-name cb1)))

  (assert-false (cl-flash-loans:get-callback "0xNONEXISTENT")))

(deftest test-execute-callback
  "Test callback execution."
  (cl-flash-loans:clear-flash-registries)
  (let ((callback (cl-flash-loans:make-flash-loan-callback
                   :receiver-address "0xRECEIVER"
                   :assets '("0xA" "0xB")
                   :amounts '(1000 2000)
                   :premiums '(9 18)
                   :initiator "0xINITIATOR")))
    (let ((result (cl-flash-loans:execute-callback
                   callback
                   (lambda (assets amounts premiums initiator params)
                     (declare (ignore params))
                     (list :assets assets
                           :amounts amounts
                           :premiums premiums
                           :initiator initiator)))))
      (assert-true (cl-flash-loans:callback-result-success result))
      (assert-true (cl-flash-loans:callback-result-return-value result)))))

;;; ============================================================================
;;; Flash Loan Request Tests
;;; ============================================================================

(deftest test-make-flash-loan-request
  "Test flash loan request creation."
  (let ((request (cl-flash-loans:make-flash-loan-request
                  :initiator "0xINITIATOR"
                  :receiver "0xRECEIVER"
                  :assets '("0xTOKEN")
                  :amounts '(1000000))))
    (assert-true request "Request should be created")
    (assert-equal "0xINITIATOR"
                  (cl-flash-loans:flash-loan-request-initiator request))
    (assert-equal "0xRECEIVER"
                  (cl-flash-loans:flash-loan-request-receiver request))
    (assert-equal '("0xTOKEN")
                  (cl-flash-loans:flash-loan-request-assets request))
    (assert-equal '(1000000)
                  (cl-flash-loans:flash-loan-request-amounts request))
    ;; Premiums should be auto-calculated
    (assert-true (cl-flash-loans:flash-loan-request-premiums request))))

(deftest test-request-validation
  "Test request validation."
  (assert-error
   (lambda ()
     (cl-flash-loans:validate-flash-loan-request nil))
   'cl-flash-loans:invalid-request-error
   "Should reject nil request")

  (assert-error
   (lambda ()
     (cl-flash-loans:validate-flash-loan-request
      (cl-flash-loans:make-flash-loan-request
       :initiator "0x"
       :assets nil
       :amounts nil)))
   'cl-flash-loans:invalid-request-error
   "Should reject request without assets"))

(deftest test-request-array-mismatch
  "Test request with mismatched arrays."
  (assert-error
   (lambda ()
     (cl-flash-loans:make-flash-loan-request
      :initiator "0x"
      :assets '("0xA" "0xB")
      :amounts '(100)))  ; Only one amount
   'cl-flash-loans:invalid-request-error))

;;; ============================================================================
;;; Flash Loan Execution Tests
;;; ============================================================================

(deftest test-execute-flash-loan-simple
  "Test simple flash loan execution."
  (cl-flash-loans:clear-flash-registries)

  (let* ((called nil)
         (amount (expt 10 18))
         (response (cl-flash-loans:execute-flash-loan-simple
                    '("0xTOKEN")
                    (list amount)
                    :initiator "0xBORROWER"
                    :callback-fn (lambda (assets amounts premiums params)
                                   (declare (ignore assets amounts premiums params))
                                   (setf called t)
                                   t))))
    (assert-true called "Callback should be called")
    (assert-true (cl-flash-loans:flash-loan-response-success response))
    (assert-equal '("0xTOKEN")
                  (cl-flash-loans:flash-loan-response-assets-borrowed response))
    (assert-equal (list amount)
                  (cl-flash-loans:flash-loan-response-amounts-borrowed response))))

(deftest test-execute-flash-loan-with-pool
  "Test flash loan with pool."
  (cl-flash-loans:clear-flash-registries)

  (let* ((amount (expt 10 18))
         (pool (cl-flash-loans:create-flash-pool :name "Test Pool")))
    (cl-flash-loans:add-pool-asset pool "0xTOKEN" :liquidity (* 10 amount))

    (let ((request (cl-flash-loans:make-flash-loan-request
                    :initiator "0xBORROWER"
                    :assets '("0xTOKEN")
                    :amounts (list amount))))
      (let ((response (cl-flash-loans:execute-flash-loan
                       request
                       :pool pool
                       :callback-fn (lambda (assets amounts premiums params)
                                      (declare (ignore assets amounts premiums params))
                                      t))))
        (assert-true (cl-flash-loans:flash-loan-response-success response))
        ;; Pool stats should be updated
        (assert-true (> (cl-flash-loans:flash-loan-pool-total-borrowed pool) 0))
        (assert-true (> (cl-flash-loans:flash-loan-pool-total-fees-collected pool) 0))))))

(deftest test-execute-flash-loan-callback-failure
  "Test flash loan with callback failure."
  (cl-flash-loans:clear-flash-registries)

  (let ((response (cl-flash-loans:execute-flash-loan-simple
                   '("0xTOKEN")
                   (list (expt 10 18))
                   :initiator "0xBORROWER"
                   :callback-fn (lambda (assets amounts premiums params)
                                  (declare (ignore assets amounts premiums params))
                                  nil))))  ; Return failure
    (assert-false (cl-flash-loans:flash-loan-response-success response))
    (assert-true (cl-flash-loans:flash-loan-response-error-message response))))

(deftest test-simulate-flash-loan
  "Test flash loan simulation."
  (let ((request (cl-flash-loans:make-flash-loan-request
                  :initiator "0xBORROWER"
                  :assets '("0xA" "0xB")
                  :amounts (list (expt 10 18) (* 2 (expt 10 18))))))
    (let ((response (cl-flash-loans:simulate-flash-loan request)))
      (assert-true (cl-flash-loans:flash-loan-response-success response))
      (assert-equal 2 (length (cl-flash-loans:flash-loan-response-assets-borrowed response)))
      (assert-true (> (cl-flash-loans:flash-loan-response-total-premium response) 0)))))

;;; ============================================================================
;;; Fee Calculation Tests
;;; ============================================================================

(deftest test-calculate-premium
  "Test premium calculation."
  (let ((premium (cl-flash-loans:calculate-flash-loan-premium
                  1000000000000000000  ; 1 token at 18 decimals
                  :fee-rate 9)))       ; 0.09%
    (assert-equal 900000000000000 premium))) ; 0.0009 tokens

(deftest test-calculate-total-premium
  "Test total premium for multiple amounts."
  (let ((total (cl-flash-loans:calculate-total-premium
                '(1000000000000000000 2000000000000000000)
                :fee-rate 9)))
    (assert-equal 2700000000000000 total))) ; 0.0027 tokens

(deftest test-get-fee-tier
  "Test fee tier determination."
  (let ((standard (cl-flash-loans:get-fee-tier 0)))
    (assert-equal 0 (cl-flash-loans:flash-fee-tier-id standard))
    (assert-equal "Standard" (cl-flash-loans:flash-fee-tier-name standard)))

  (let ((gold (cl-flash-loans:get-fee-tier (* 1000001 (expt 10 18)))))
    (assert-equal 3 (cl-flash-loans:flash-fee-tier-id gold))
    (assert-equal "Gold" (cl-flash-loans:flash-fee-tier-name gold))))

;;; ============================================================================
;;; Reentrancy Protection Tests
;;; ============================================================================

(deftest test-reentrancy-guard
  "Test reentrancy guard."
  (let ((guard (cl-flash-loans:make-reentrancy-guard)))
    (assert-false (cl-flash-loans:check-reentrancy-lock guard))

    (cl-flash-loans:acquire-reentrancy-lock guard "0xCALLER")
    (assert-true (cl-flash-loans:check-reentrancy-lock guard))
    (assert-equal 1 (cl-flash-loans:reentrancy-guard-call-depth guard))

    (cl-flash-loans:release-reentrancy-lock guard)
    (assert-false (cl-flash-loans:check-reentrancy-lock guard))
    (assert-equal 0 (cl-flash-loans:reentrancy-guard-call-depth guard))))

(deftest test-reentrancy-depth-limit
  "Test reentrancy depth limit."
  (let ((guard (cl-flash-loans:make-reentrancy-guard)))
    ;; Acquire up to max depth
    (dotimes (i cl-flash-loans:+max-reentrancy-depth+)
      (cl-flash-loans:acquire-reentrancy-lock guard "0xCALLER"))

    ;; One more should fail
    (assert-error
     (lambda ()
       (cl-flash-loans:acquire-reentrancy-lock guard "0xCALLER"))
     'cl-flash-loans:reentrancy-detected-error)))

;;; ============================================================================
;;; Limit Tests
;;; ============================================================================

(deftest test-global-limits
  "Test global limits checking."
  (cl-flash-loans:clear-flash-registries)
  (setf cl-flash-loans:*global-limits*
        (cl-flash-loans:make-global-limits
         :max-total-borrowed 1000000
         :max-per-transaction 100000))

  ;; Should pass
  (assert-true (cl-flash-loans:check-borrowing-limits 50000))

  ;; Should fail - exceeds per-transaction
  (assert-error
   (lambda () (cl-flash-loans:check-borrowing-limits 150000))
   'cl-flash-loans:limit-exceeded-error))

;;; ============================================================================
;;; Test Runner
;;; ============================================================================

(defun run-tests ()
  "Run all tests and report results."
  (setf *test-results* nil)

  ;; Run all tests
  (let ((tests '(test-flash-wad-mul
                 test-flash-wad-div
                 test-flash-percent-mul
                 test-flash-get-timestamp
                 test-create-pool
                 test-pool-registry
                 test-add-pool-asset
                 test-pool-liquidity
                 test-pool-pause
                 test-register-callback
                 test-callback-lookup
                 test-execute-callback
                 test-make-flash-loan-request
                 test-request-validation
                 test-request-array-mismatch
                 test-execute-flash-loan-simple
                 test-execute-flash-loan-with-pool
                 test-execute-flash-loan-callback-failure
                 test-simulate-flash-loan
                 test-calculate-premium
                 test-calculate-total-premium
                 test-get-fee-tier
                 test-reentrancy-guard
                 test-reentrancy-depth-limit
                 test-global-limits)))

    (format t "~%Running ~D tests...~%~%" (length tests))

    (dolist (test tests)
      (funcall test))

    ;; Report results
    (let ((passed 0)
          (failed 0))
      (dolist (result (reverse *test-results*))
        (if (eq (cdr result) :pass)
            (progn
              (format t "  PASS: ~A~%" (car result))
              (incf passed))
            (progn
              (format t "  FAIL: ~A - ~A~%" (car result) (cdr result))
              (incf failed))))

      (format t "~%Results: ~D passed, ~D failed~%" passed failed)

      ;; Return success status
      (zerop failed))))
