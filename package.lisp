;;;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;;;; SPDX-License-Identifier: BSD-3-Clause

;;;; ============================================================================
;;;; CL-FLASH-LOANS - Package Definition
;;;; ============================================================================
;;;;
;;;; Atomic flash loan protocol with callback handling.
;;;;
;;;; Flash loans enable borrowing assets without collateral, provided the
;;;; borrowed amount plus fees is returned within the same transaction.
;;;; This enables powerful DeFi strategies including:
;;;; - Arbitrage across DEXes and lending protocols
;;;; - Collateral swaps without unwinding positions
;;;; - Self-liquidation to avoid penalties
;;;; - Leveraged positions without upfront capital
;;;;
;;;; Author: CLPIC Development Team
;;;; License: MIT
;;;; ============================================================================

(in-package #:cl-user)

(defpackage #:cl-flash-loans
  (:use #:cl)
  (:nicknames #:flash-loans)

  ;; -------------------------------------------------------------------------
  ;; Mathematical Constants and Precision
  ;; -------------------------------------------------------------------------
  (:export
   #:+flash-wad+
   #:+flash-ray+
   #:+flash-half-wad+
   #:+flash-half-ray+
   #:+flash-percent-factor+
   #:+flash-max-uint256+
   #:flash-wad-mul
   #:flash-wad-div
   #:flash-ray-mul
   #:flash-ray-div
   #:flash-percent-mul
   #:flash-percent-div
   #:flash-get-timestamp)

  ;; -------------------------------------------------------------------------
  ;; Protocol Constants
  ;; -------------------------------------------------------------------------
  (:export
   #:+default-flash-fee+
   #:+min-flash-fee+
   #:+max-flash-fee+
   #:+protocol-fee-share+
   #:+lp-fee-share+
   #:+max-flash-loan-assets+
   #:+max-flash-loan-amount+
   #:+min-flash-loan-amount+
   #:+max-execution-gas+
   #:+flash-loan-timeout+
   #:+max-reentrancy-depth+
   #:+max-operations-per-tx+
   #:+cooldown-period+
   #:+rate-limit-window+
   #:+max-loans-per-window+)

  ;; -------------------------------------------------------------------------
  ;; Flash Loan Mode Constants
  ;; -------------------------------------------------------------------------
  (:export
   #:+flash-mode-standard+
   #:+flash-mode-stable-debt+
   #:+flash-mode-variable-debt+
   #:+flash-mode-collateral-swap+
   #:+flash-mode-arbitrage+
   #:+flash-mode-liquidation+)

  ;; -------------------------------------------------------------------------
  ;; Core Flash Loan Types
  ;; -------------------------------------------------------------------------
  (:export
   ;; Flash Loan Request
   #:flash-loan-request
   #:make-flash-loan-request
   #:flash-loan-request-p
   #:copy-flash-loan-request
   #:flash-loan-request-id
   #:flash-loan-request-initiator
   #:flash-loan-request-receiver
   #:flash-loan-request-assets
   #:flash-loan-request-amounts
   #:flash-loan-request-premiums
   #:flash-loan-request-modes
   #:flash-loan-request-on-behalf-of
   #:flash-loan-request-params
   #:flash-loan-request-referral-code
   #:flash-loan-request-deadline
   #:flash-loan-request-nonce
   #:flash-loan-request-signature
   #:flash-loan-request-created-at

   ;; Flash Loan Response
   #:flash-loan-response
   #:make-flash-loan-response
   #:flash-loan-response-p
   #:copy-flash-loan-response
   #:flash-loan-response-request-id
   #:flash-loan-response-success
   #:flash-loan-response-assets-borrowed
   #:flash-loan-response-amounts-borrowed
   #:flash-loan-response-premiums-paid
   #:flash-loan-response-total-premium
   #:flash-loan-response-execution-time
   #:flash-loan-response-gas-used
   #:flash-loan-response-error-message
   #:flash-loan-response-callback-result
   #:flash-loan-response-tx-hash

   ;; Flash Loan Context
   #:flash-loan-context
   #:make-flash-loan-context
   #:flash-loan-context-p
   #:copy-flash-loan-context
   #:flash-loan-context-id
   #:flash-loan-context-request
   #:flash-loan-context-pool-id
   #:flash-loan-context-initiator
   #:flash-loan-context-receiver
   #:flash-loan-context-assets
   #:flash-loan-context-amounts
   #:flash-loan-context-premiums
   #:flash-loan-context-params
   #:flash-loan-context-state
   #:flash-loan-context-start-time
   #:flash-loan-context-deadline
   #:flash-loan-context-reentrancy-guard
   #:flash-loan-context-call-depth
   #:flash-loan-context-operations
   #:flash-loan-context-checkpoints

   ;; Flash Loan Mode
   #:flash-loan-mode
   #:make-flash-loan-mode
   #:flash-loan-mode-p
   #:flash-loan-mode-id
   #:flash-loan-mode-name
   #:flash-loan-mode-description
   #:flash-loan-mode-requires-repayment
   #:flash-loan-mode-can-open-debt)

  ;; -------------------------------------------------------------------------
  ;; Flash Loan Pool Types
  ;; -------------------------------------------------------------------------
  (:export
   #:flash-loan-pool
   #:make-flash-loan-pool
   #:flash-loan-pool-p
   #:copy-flash-loan-pool
   #:flash-loan-pool-id
   #:flash-loan-pool-name
   #:flash-loan-pool-protocol
   #:flash-loan-pool-assets
   #:flash-loan-pool-reserves
   #:flash-loan-pool-total-borrowed
   #:flash-loan-pool-total-fees-collected
   #:flash-loan-pool-fee-rate
   #:flash-loan-pool-protocol-fee-rate
   #:flash-loan-pool-is-active
   #:flash-loan-pool-is-paused
   #:flash-loan-pool-authorized-borrowers
   #:flash-loan-pool-borrower-limits
   #:flash-loan-pool-asset-limits
   #:flash-loan-pool-whitelist-only
   #:flash-loan-pool-config
   #:flash-loan-pool-created-at
   #:flash-loan-pool-last-update

   ;; Pool Asset
   #:flash-pool-asset
   #:make-flash-pool-asset
   #:flash-pool-asset-p
   #:copy-flash-pool-asset
   #:flash-pool-asset-address
   #:flash-pool-asset-symbol
   #:flash-pool-asset-decimals
   #:flash-pool-asset-available-liquidity
   #:flash-pool-asset-total-borrowed
   #:flash-pool-asset-total-fees
   #:flash-pool-asset-fee-rate
   #:flash-pool-asset-borrow-cap
   #:flash-pool-asset-is-enabled
   #:flash-pool-asset-oracle-address
   #:flash-pool-asset-last-borrow-time

   ;; Pool Configuration
   #:flash-pool-config
   #:make-flash-pool-config
   #:flash-pool-config-p
   #:copy-flash-pool-config
   #:flash-pool-config-default-fee-rate
   #:flash-pool-config-protocol-fee-share
   #:flash-pool-config-max-assets-per-loan
   #:flash-pool-config-max-amount-per-asset
   #:flash-pool-config-require-whitelist
   #:flash-pool-config-rate-limit-enabled
   #:flash-pool-config-rate-limit-window
   #:flash-pool-config-rate-limit-max-loans
   #:flash-pool-config-cooldown-enabled
   #:flash-pool-config-cooldown-period)

  ;; -------------------------------------------------------------------------
  ;; Callback Interface Types
  ;; -------------------------------------------------------------------------
  (:export
   #:flash-loan-callback
   #:make-flash-loan-callback
   #:flash-loan-callback-p
   #:copy-flash-loan-callback
   #:flash-loan-callback-id
   #:flash-loan-callback-receiver-address
   #:flash-loan-callback-function-name
   #:flash-loan-callback-assets
   #:flash-loan-callback-amounts
   #:flash-loan-callback-premiums
   #:flash-loan-callback-initiator
   #:flash-loan-callback-params
   #:flash-loan-callback-gas-limit
   #:flash-loan-callback-timeout

   #:callback-result
   #:make-callback-result
   #:callback-result-p
   #:copy-callback-result
   #:callback-result-success
   #:callback-result-return-value
   #:callback-result-gas-used
   #:callback-result-execution-time
   #:callback-result-error-code
   #:callback-result-error-message
   #:callback-result-logs

   #:callback-registry-entry
   #:make-callback-registry-entry
   #:callback-registry-entry-p
   #:callback-registry-entry-address
   #:callback-registry-entry-name
   #:callback-registry-entry-abi-hash
   #:callback-registry-entry-is-verified
   #:callback-registry-entry-is-trusted
   #:callback-registry-entry-total-calls
   #:callback-registry-entry-success-rate
   #:callback-registry-entry-avg-gas-used
   #:callback-registry-entry-registered-at)

  ;; -------------------------------------------------------------------------
  ;; Fee Types
  ;; -------------------------------------------------------------------------
  (:export
   #:flash-fee-structure
   #:make-flash-fee-structure
   #:flash-fee-structure-p
   #:flash-fee-structure-base-fee
   #:flash-fee-structure-protocol-fee
   #:flash-fee-structure-lp-fee
   #:flash-fee-structure-referral-fee
   #:flash-fee-structure-discount
   #:flash-fee-structure-net-fee
   #:flash-fee-structure-tier

   #:flash-fee-tier
   #:make-flash-fee-tier
   #:flash-fee-tier-p
   #:flash-fee-tier-id
   #:flash-fee-tier-name
   #:flash-fee-tier-min-volume
   #:flash-fee-tier-fee-rate
   #:flash-fee-tier-discount-rate
   #:flash-fee-tier-benefits)

  ;; -------------------------------------------------------------------------
  ;; Limit Types
  ;; -------------------------------------------------------------------------
  (:export
   #:borrowing-limit
   #:make-borrowing-limit
   #:borrowing-limit-p
   #:borrowing-limit-id
   #:borrowing-limit-limit-type
   #:borrowing-limit-asset
   #:borrowing-limit-max-amount
   #:borrowing-limit-current-usage
   #:borrowing-limit-reset-period
   #:borrowing-limit-last-reset
   #:borrowing-limit-is-active

   #:global-limits
   #:make-global-limits
   #:global-limits-p
   #:global-limits-max-total-borrowed
   #:global-limits-current-total-borrowed
   #:global-limits-max-per-transaction
   #:global-limits-max-per-block
   #:global-limits-current-block-usage
   #:global-limits-max-per-user-daily
   #:global-limits-circuit-breaker-threshold
   #:global-limits-circuit-breaker-triggered

   #:user-limits
   #:make-user-limits
   #:user-limits-p
   #:user-limits-address
   #:user-limits-max-per-loan
   #:user-limits-max-daily
   #:user-limits-max-weekly
   #:user-limits-current-daily-usage
   #:user-limits-current-weekly-usage
   #:user-limits-daily-reset-time
   #:user-limits-weekly-reset-time
   #:user-limits-is-whitelisted
   #:user-limits-is-blacklisted
   #:user-limits-tier

   #:asset-limits
   #:make-asset-limits
   #:asset-limits-p
   #:asset-limits-asset-address
   #:asset-limits-max-borrow
   #:asset-limits-max-utilization
   #:asset-limits-current-borrowed
   #:asset-limits-available-liquidity
   #:asset-limits-cooldown-period
   #:asset-limits-last-borrow-time)

  ;; -------------------------------------------------------------------------
  ;; Protection Types
  ;; -------------------------------------------------------------------------
  (:export
   #:reentrancy-guard
   #:make-reentrancy-guard
   #:reentrancy-guard-p
   #:copy-reentrancy-guard
   #:reentrancy-guard-id
   #:reentrancy-guard-status
   #:reentrancy-guard-call-depth
   #:reentrancy-guard-max-depth
   #:reentrancy-guard-locked-by
   #:reentrancy-guard-lock-time
   #:reentrancy-guard-call-stack

   #:security-policy
   #:make-security-policy
   #:security-policy-p
   #:security-policy-id
   #:security-policy-name
   #:security-policy-max-reentrancy-depth
   #:security-policy-max-call-depth
   #:security-policy-max-operations
   #:security-policy-require-signature
   #:security-policy-require-whitelist
   #:security-policy-block-on-suspicious
   #:security-policy-rate-limit-config
   #:security-policy-circuit-breakers

   #:circuit-breaker
   #:make-circuit-breaker
   #:circuit-breaker-p
   #:circuit-breaker-id
   #:circuit-breaker-name
   #:circuit-breaker-trigger-condition
   #:circuit-breaker-threshold
   #:circuit-breaker-current-value
   #:circuit-breaker-is-triggered
   #:circuit-breaker-trigger-time
   #:circuit-breaker-cooldown-period
   #:circuit-breaker-auto-reset)

  ;; -------------------------------------------------------------------------
  ;; Core Operations
  ;; -------------------------------------------------------------------------
  (:export
   ;; Loan Execution
   #:execute-flash-loan
   #:execute-flash-loan-simple
   #:prepare-flash-loan
   #:validate-flash-loan-request
   #:calculate-flash-loan-premium
   #:simulate-flash-loan

   ;; Pool Operations
   #:create-flash-pool
   #:get-flash-pool
   #:add-pool-asset
   #:remove-pool-asset
   #:get-pool-liquidity
   #:pause-flash-pool
   #:unpause-flash-pool

   ;; Callback Operations
   #:register-callback
   #:unregister-callback
   #:execute-callback
   #:validate-callback-params

   ;; Fee Operations
   #:calculate-flash-fee
   #:calculate-total-premium
   #:get-fee-tier

   ;; Limit Operations
   #:check-borrowing-limits
   #:update-usage
   #:reset-limits

   ;; Protection Operations
   #:acquire-reentrancy-lock
   #:release-reentrancy-lock
   #:check-reentrancy-lock)

  ;; -------------------------------------------------------------------------
  ;; Error Conditions
  ;; -------------------------------------------------------------------------
  (:export
   #:flash-loan-error
   #:flash-loan-error-code
   #:flash-loan-error-message
   #:flash-loan-error-details
   #:invalid-request-error
   #:invalid-amount-error
   #:invalid-asset-error
   #:deadline-exceeded-error
   #:execution-failed-error
   #:callback-failed-error
   #:repayment-failed-error
   #:insufficient-funds-error
   #:limit-exceeded-error
   #:rate-limit-error
   #:pool-not-found-error
   #:pool-paused-error
   #:insufficient-liquidity-error
   #:reentrancy-detected-error
   #:unauthorized-error)

  ;; -------------------------------------------------------------------------
  ;; Global State
  ;; -------------------------------------------------------------------------
  (:export
   #:*flash-pool-registry*
   #:*callback-registry*
   #:*global-limits*
   #:clear-flash-registries))

;;; ============================================================================
;;; Test Package
;;; ============================================================================

(defpackage #:cl-flash-loans.test
  (:use #:cl #:cl-flash-loans)
  (:export #:run-tests))
