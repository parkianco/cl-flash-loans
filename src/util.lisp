;;;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;;;; SPDX-License-Identifier: BSD-3-Clause

;;;; ============================================================================
;;;; CL-FLASH-LOANS - Utility Functions and Constants
;;;; ============================================================================
;;;;
;;;; Core mathematical utilities and protocol constants for flash loan
;;;; calculations. Provides fixed-point arithmetic with WAD (1e18) and
;;;; RAY (1e27) precision units.
;;;;
;;;; Author: CLPIC Development Team
;;;; License: MIT
;;;; ============================================================================

(in-package #:cl-flash-loans)

;;; ============================================================================
;;; Mathematical Constants and Precision
;;; ============================================================================

(defconstant +flash-wad+ (expt 10 18)
  "Standard precision unit (1e18) for token amounts and calculations.")

(defconstant +flash-ray+ (expt 10 27)
  "High precision unit (1e27) for interest rate and fee calculations.")

(defconstant +flash-half-wad+ (floor +flash-wad+ 2)
  "Half of WAD (5e17) for rounding in WAD arithmetic.")

(defconstant +flash-half-ray+ (floor +flash-ray+ 2)
  "Half of RAY (5e26) for rounding in RAY arithmetic.")

(defconstant +flash-percent-factor+ 10000
  "Basis points factor (1e4) - 100% = 10000 basis points.")

(defconstant +flash-max-uint256+ (1- (expt 2 256))
  "Maximum value for a 256-bit unsigned integer.")

;;; ============================================================================
;;; Protocol Constants
;;; ============================================================================

;;; Fee Constants (in basis points)
(defconstant +default-flash-fee+ 9
  "Default flash loan fee: 0.09% (9 basis points).")

(defconstant +min-flash-fee+ 1
  "Minimum flash loan fee: 0.01% (1 basis point).")

(defconstant +max-flash-fee+ 100
  "Maximum flash loan fee: 1.00% (100 basis points).")

(defconstant +protocol-fee-share+ 3000
  "Protocol's share of fees: 30% (3000 basis points).")

(defconstant +lp-fee-share+ 7000
  "LP's share of fees: 70% (7000 basis points).")

;;; Execution Constants
(defconstant +max-flash-loan-assets+ 10
  "Maximum number of assets that can be borrowed in a single flash loan.")

(defconstant +max-flash-loan-amount+ (expt 10 30)
  "Maximum single asset amount: ~1 trillion tokens (at 18 decimals).")

(defconstant +min-flash-loan-amount+ (expt 10 15)
  "Minimum flash loan amount: 0.001 tokens (at 18 decimals).")

(defconstant +max-execution-gas+ 30000000
  "Maximum gas for flash loan execution: 30M gas.")

(defconstant +flash-loan-timeout+ 300
  "Transaction timeout: 300 seconds (5 minutes).")

;;; Protection Constants
(defconstant +max-reentrancy-depth+ 3
  "Maximum call depth for reentrancy protection.")

(defconstant +max-operations-per-tx+ 50
  "Maximum operations per transaction.")

(defconstant +cooldown-period+ 60
  "Cooldown period between flash loans: 60 seconds.")

(defconstant +rate-limit-window+ 3600
  "Rate limiting window: 3600 seconds (1 hour).")

(defconstant +max-loans-per-window+ 100
  "Maximum loans per rate limit window.")

;;; ============================================================================
;;; Flash Loan Mode Constants
;;; ============================================================================

(defconstant +flash-mode-standard+ 0
  "Standard flash loan mode: must repay within same transaction.")

(defconstant +flash-mode-stable-debt+ 1
  "Convert flash loan to stable rate debt position.")

(defconstant +flash-mode-variable-debt+ 2
  "Convert flash loan to variable rate debt position.")

(defconstant +flash-mode-collateral-swap+ 3
  "Collateral swap mode for position restructuring.")

(defconstant +flash-mode-arbitrage+ 4
  "Arbitrage execution mode.")

(defconstant +flash-mode-liquidation+ 5
  "Flash liquidation mode.")

;;; ============================================================================
;;; Fixed-Point Arithmetic Utilities
;;; ============================================================================

(defun flash-wad-mul (a b)
  "Multiply two WAD-precision numbers with proper rounding.
   Result = (a * b + half_wad) / wad"
  (declare (type integer a b))
  (if (or (zerop a) (zerop b))
      0
      (let ((product (* a b)))
        (floor (+ product +flash-half-wad+) +flash-wad+))))

(defun flash-wad-div (a b)
  "Divide two WAD-precision numbers with proper rounding.
   Result = (a * wad + b/2) / b"
  (declare (type integer a b))
  (when (zerop b)
    (error 'division-by-zero :operation 'flash-wad-div :operands (list a b)))
  (let ((half-b (floor b 2)))
    (floor (+ (* a +flash-wad+) half-b) b)))

(defun flash-ray-mul (a b)
  "Multiply two RAY-precision numbers with proper rounding.
   Result = (a * b + half_ray) / ray"
  (declare (type integer a b))
  (if (or (zerop a) (zerop b))
      0
      (let ((product (* a b)))
        (floor (+ product +flash-half-ray+) +flash-ray+))))

(defun flash-ray-div (a b)
  "Divide two RAY-precision numbers with proper rounding.
   Result = (a * ray + b/2) / b"
  (declare (type integer a b))
  (when (zerop b)
    (error 'division-by-zero :operation 'flash-ray-div :operands (list a b)))
  (let ((half-b (floor b 2)))
    (floor (+ (* a +flash-ray+) half-b) b)))

(defun flash-percent-mul (value percentage)
  "Multiply a value by a percentage in basis points.
   Result = (value * percentage + half_percent) / percent_factor"
  (declare (type integer value percentage))
  (if (or (zerop value) (zerop percentage))
      0
      (floor (+ (* value percentage) (floor +flash-percent-factor+ 2))
             +flash-percent-factor+)))

(defun flash-percent-div (value percentage)
  "Divide a value by a percentage in basis points.
   Result = (value * percent_factor + percentage/2) / percentage"
  (declare (type integer value percentage))
  (when (zerop percentage)
    (error 'division-by-zero :operation 'flash-percent-div :operands (list value percentage)))
  (floor (+ (* value +flash-percent-factor+) (floor percentage 2)) percentage))

(defun flash-get-timestamp ()
  "Get the current Unix timestamp in seconds."
  (- (get-universal-time) 2208988800))

;;; ============================================================================
;;; ID Generation
;;; ============================================================================

(defun generate-flash-loan-id (initiator timestamp)
  "Generate a unique flash loan request ID."
  (format nil "FLASH-~8,'0X-~8,'0X"
          (sxhash (or initiator "unknown"))
          (logand (or timestamp (flash-get-timestamp)) #xFFFFFFFF)))

(defun generate-pool-id (protocol timestamp)
  "Generate a unique pool ID."
  (format nil "FLASH-POOL-~A-~8,'0X"
          (string-upcase protocol)
          (logand timestamp #xFFFFFFFF)))

(defun generate-callback-id (address timestamp)
  "Generate a unique callback ID."
  (format nil "CB-~8,'0X-~8,'0X"
          (sxhash (or address "unknown"))
          (logand timestamp #xFFFFFFFF)))

;;; ============================================================================
;;; Global State
;;; ============================================================================

(defvar *flash-pool-registry* (make-hash-table :test 'equal)
  "Registry of all flash loan pools, keyed by pool ID.")

(defvar *callback-registry* (make-hash-table :test 'equal)
  "Registry of registered callback contracts, keyed by address.")

(defvar *global-limits* nil
  "Global borrowing limits.")

(defun clear-flash-registries ()
  "Clear all flash loan registries. Use for testing only."
  (clrhash *flash-pool-registry*)
  (clrhash *callback-registry*)
  (setf *global-limits* nil)
  nil)
