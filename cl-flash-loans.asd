;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;; SPDX-License-Identifier: BSD-3-Clause

;;;; ============================================================================
;;;; CL-FLASH-LOANS - Atomic Flash Loan Protocol for Common Lisp
;;;; ============================================================================
;;;;
;;;; A standalone, dependency-free flash loan protocol implementation in pure
;;;; Common Lisp. Provides atomic loan execution with callback handling for
;;;; DeFi applications.
;;;;
;;;; Features:
;;;; - Uncollateralized flash loans with atomic execution
;;;; - Callback interface for custom operation execution
;;;; - Liquidity pool management
;;;; - Fee calculation and distribution
;;;; - Reentrancy protection
;;;; - Borrowing limits and rate limiting
;;;;
;;;; Author: Parkian Company LLC
;;;; License: MIT
;;;; ============================================================================

(asdf:defsystem #:"cl-flash-loans"
  :name "CL-FLASH-LOANS"
  :version "0.1.0"
  :author "Parkian Company LLC"
  :license "MIT"
  :description "Atomic flash loan protocol for Common Lisp"
  :long-description "A standalone, pure Common Lisp implementation of an atomic
flash loan protocol. Provides loan execution, callback handling, pool management,
fee calculation, and security protections without external dependencies."

  :class :package-inferred-system
  :defsystem-depends-on ()
  :depends-on ()

  :components
  ((:file "package")
   (:module "src"
    :serial t
    :components
    ((:file "util")
     (:file "loan")
     (:file "callback")
     (:file "pool"))))

  :in-order-to ((asdf:test-op (test-op "cl-flash-loans/test"))))

(asdf:defsystem #:"cl-flash-loans/test"
  :name "CL-FLASH-LOANS Tests"
  :version "0.1.0"
  :author "Parkian Company LLC"
  :license "MIT"
  :description "Test suite for cl-flash-loans"
  :depends-on ("cl-flash-loans")
  :components
  ((:module "test"
    :components
    ((:file "test-flash"))))
  :perform (asdf:test-op (op c)
             (let ((result (uiop:symbol-call :cl-flash-loans.test :run-tests)))
               (unless result
                 (error "Tests failed")))))
