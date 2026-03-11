;;;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;;;; SPDX-License-Identifier: BSD-3-Clause

;;;; ============================================================================
;;;; CL-FLASH-LOANS - Callback Protocol
;;;; ============================================================================
;;;;
;;;; Callback interface handling for flash loan execution. Manages callback
;;;; registration, validation, and execution.
;;;;
;;;; Author: CLPIC Development Team
;;;; License: MIT
;;;; ============================================================================

(in-package #:cl-flash-loans)

;;; ============================================================================
;;; Callback Types
;;; ============================================================================

(defstruct (flash-loan-callback
            (:constructor make-flash-loan-callback)
            (:copier copy-flash-loan-callback))
  "Represents a flash loan callback configuration.

   The callback is invoked after funds are transferred to the receiver,
   allowing the receiver to use the funds before repayment is required."
  (id nil :type (or null string))
  (receiver-address nil :type (or null string))
  (function-name "executeOperation" :type string)
  (assets nil :type list)
  (amounts nil :type list)
  (premiums nil :type list)
  (initiator nil :type (or null string))
  (params nil)
  (gas-limit +max-execution-gas+ :type integer)
  (timeout +flash-loan-timeout+ :type integer))

(defstruct (callback-result
            (:constructor make-callback-result)
            (:copier copy-callback-result))
  "Result of a callback execution."
  (success nil :type boolean)
  (return-value nil)
  (gas-used 0 :type integer)
  (execution-time 0 :type integer)
  (error-code nil :type (or null string))
  (error-message nil :type (or null string))
  (logs nil :type list))

(defstruct (callback-registry-entry
            (:constructor make-callback-registry-entry)
            (:copier copy-callback-registry-entry))
  "Registry entry for a callback contract."
  (address nil :type (or null string))
  (name "" :type string)
  (abi-hash nil :type (or null string))
  (is-verified nil :type boolean)
  (is-trusted nil :type boolean)
  (total-calls 0 :type integer)
  (success-rate 10000 :type integer)
  (avg-gas-used 0 :type integer)
  (registered-at 0 :type integer))

;;; ============================================================================
;;; Callback Registry
;;; ============================================================================

(defun register-callback (address &key name abi-hash (trusted nil) (verified nil))
  "Register a callback contract in the registry.

   Parameters:
   - address: Contract address
   - name: Human-readable name
   - abi-hash: Hash of contract ABI for verification
   - trusted: Whether callback is in trusted list
   - verified: Whether callback is verified

   Returns: The registry entry"
  (unless address
    (error 'invalid-request-error
           :message "Callback address is required"))

  (let ((entry (make-callback-registry-entry
                :address address
                :name (or name "")
                :abi-hash abi-hash
                :is-verified verified
                :is-trusted trusted
                :total-calls 0
                :success-rate 10000
                :avg-gas-used 0
                :registered-at (flash-get-timestamp))))
    (setf (gethash address *callback-registry*) entry)
    entry))

(defun unregister-callback (address)
  "Remove a callback from the registry.

   Parameters:
   - address: Contract address to remove

   Returns: T if removed, NIL if not found"
  (remhash address *callback-registry*))

(defun get-callback (address)
  "Get a callback registry entry by address.

   Parameters:
   - address: Contract address

   Returns: callback-registry-entry or NIL"
  (gethash address *callback-registry*))

(defun list-callbacks ()
  "List all registered callbacks.

   Returns: List of callback-registry-entry structures"
  (let ((callbacks nil))
    (maphash (lambda (k v)
               (declare (ignore k))
               (push v callbacks))
             *callback-registry*)
    callbacks))

;;; ============================================================================
;;; Callback Validation
;;; ============================================================================

(defun validate-callback-params (callback)
  "Validate callback parameters before execution.

   Parameters:
   - callback: flash-loan-callback structure

   Returns: T if valid, signals error otherwise"
  (unless callback
    (error 'invalid-request-error
           :message "Callback cannot be nil"))

  (unless (flash-loan-callback-receiver-address callback)
    (error 'invalid-request-error
           :message "Callback receiver address is required"))

  (unless (flash-loan-callback-assets callback)
    (error 'invalid-request-error
           :message "Callback assets are required"))

  (unless (flash-loan-callback-amounts callback)
    (error 'invalid-request-error
           :message "Callback amounts are required"))

  (unless (= (length (flash-loan-callback-assets callback))
             (length (flash-loan-callback-amounts callback)))
    (error 'invalid-request-error
           :message "Assets and amounts must have same length"))

  t)

(defun check-callback-registered (address)
  "Check if a callback is registered.

   Parameters:
   - address: Contract address

   Returns: callback-registry-entry or NIL"
  (get-callback address))

(defun check-callback-trusted (address)
  "Check if a callback is trusted.

   Parameters:
   - address: Contract address

   Returns: T if trusted, NIL otherwise"
  (let ((entry (get-callback address)))
    (and entry (callback-registry-entry-is-trusted entry))))

(defun check-callback-verified (address)
  "Check if a callback is verified.

   Parameters:
   - address: Contract address

   Returns: T if verified, NIL otherwise"
  (let ((entry (get-callback address)))
    (and entry (callback-registry-entry-is-verified entry))))

;;; ============================================================================
;;; Callback Execution
;;; ============================================================================

(defun execute-callback (callback callback-fn)
  "Execute a callback with the provided function.

   This executes the callback function with the loan parameters
   and returns a callback-result.

   Parameters:
   - callback: flash-loan-callback structure
   - callback-fn: Function to execute
                  (assets amounts premiums initiator params) -> return-value

   Returns: callback-result structure"
  (validate-callback-params callback)

  (let ((start-time (get-internal-real-time))
        (entry (get-callback (flash-loan-callback-receiver-address callback))))

    ;; Update call count if registered
    (when entry
      (incf (callback-registry-entry-total-calls entry)))

    (handler-case
        (let ((result (funcall callback-fn
                               (flash-loan-callback-assets callback)
                               (flash-loan-callback-amounts callback)
                               (flash-loan-callback-premiums callback)
                               (flash-loan-callback-initiator callback)
                               (flash-loan-callback-params callback))))

          (let ((end-time (get-internal-real-time))
                (execution-time (round (* 1000
                                          (/ (- (get-internal-real-time) start-time)
                                             internal-time-units-per-second)))))

            ;; Update stats if registered
            (when entry
              ;; Update success rate (weighted average)
              (let* ((total (callback-registry-entry-total-calls entry))
                     (old-rate (callback-registry-entry-success-rate entry))
                     (new-rate (floor (+ (* old-rate (1- total)) 10000) total)))
                (setf (callback-registry-entry-success-rate entry) new-rate)))

            (make-callback-result
             :success t
             :return-value result
             :gas-used 0
             :execution-time execution-time
             :error-code nil
             :error-message nil
             :logs nil)))

      (error (e)
        ;; Update failure stats if registered
        (when entry
          (let* ((total (callback-registry-entry-total-calls entry))
                 (old-rate (callback-registry-entry-success-rate entry))
                 (new-rate (floor (* old-rate (1- total)) total)))
            (setf (callback-registry-entry-success-rate entry) new-rate)))

        (make-callback-result
         :success nil
         :return-value nil
         :gas-used 0
         :execution-time (round (* 1000
                                   (/ (- (get-internal-real-time) start-time)
                                      internal-time-units-per-second)))
         :error-code "CALLBACK_ERROR"
         :error-message (format nil "~A" e)
         :logs nil)))))

(defun execute-callback-with-timeout (callback callback-fn &key (timeout +flash-loan-timeout+))
  "Execute a callback with a timeout.

   Note: This is a placeholder implementation. In production, this would
   use threading or async execution with timeout handling.

   Parameters:
   - callback: flash-loan-callback structure
   - callback-fn: Function to execute
   - timeout: Timeout in seconds (default: +flash-loan-timeout+)

   Returns: callback-result structure"
  (declare (ignore timeout))
  ;; For now, just execute without actual timeout
  ;; In production, this would use sb-thread or similar
  (execute-callback callback callback-fn))

;;; ============================================================================
;;; Callback Statistics
;;; ============================================================================

(defun get-callback-stats (address)
  "Get statistics for a callback.

   Parameters:
   - address: Contract address

   Returns: Association list of stats or NIL if not found"
  (let ((entry (get-callback address)))
    (when entry
      `((:address . ,(callback-registry-entry-address entry))
        (:name . ,(callback-registry-entry-name entry))
        (:total-calls . ,(callback-registry-entry-total-calls entry))
        (:success-rate . ,(/ (callback-registry-entry-success-rate entry) 100.0))
        (:avg-gas-used . ,(callback-registry-entry-avg-gas-used entry))
        (:is-trusted . ,(callback-registry-entry-is-trusted entry))
        (:is-verified . ,(callback-registry-entry-is-verified entry))
        (:registered-at . ,(callback-registry-entry-registered-at entry))))))

(defun get-top-callbacks (&key (limit 10) (sort-by :total-calls))
  "Get top callbacks by specified metric.

   Parameters:
   - limit: Maximum number of results
   - sort-by: Sort metric (:total-calls, :success-rate)

   Returns: List of callback-registry-entry structures"
  (let ((callbacks (list-callbacks)))
    (subseq (sort callbacks #'>
                  :key (ecase sort-by
                         (:total-calls #'callback-registry-entry-total-calls)
                         (:success-rate #'callback-registry-entry-success-rate)))
            0 (min limit (length callbacks)))))

;;; ============================================================================
;;; Callback Builder
;;; ============================================================================

(defun build-callback (receiver assets amounts premiums initiator params)
  "Build a flash-loan-callback structure.

   Parameters:
   - receiver: Receiver address
   - assets: List of asset addresses
   - amounts: List of amounts
   - premiums: List of premiums
   - initiator: Initiator address
   - params: Callback parameters

   Returns: flash-loan-callback structure"
  (make-flash-loan-callback
   :id (generate-callback-id receiver (flash-get-timestamp))
   :receiver-address receiver
   :function-name "executeOperation"
   :assets assets
   :amounts amounts
   :premiums premiums
   :initiator initiator
   :params params
   :gas-limit +max-execution-gas+
   :timeout +flash-loan-timeout+))
