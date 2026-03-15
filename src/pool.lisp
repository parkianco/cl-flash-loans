;;;; Copyright (c) 2024-2026 Parkian Company LLC. All rights reserved.
;;;; SPDX-License-Identifier: Apache-2.0

;;;; ============================================================================
;;;; CL-FLASH-LOANS - Liquidity Pool Integration
;;;; ============================================================================
;;;;
;;;; Flash loan pool management. Handles pool creation, asset management,
;;;; liquidity tracking, and pool configuration.
;;;;
;;;; Author: CLPIC Development Team
;;;; License: MIT
;;;; ============================================================================

(in-package #:cl-flash-loans)

;;; ============================================================================
;;; Pool Asset Type
;;; ============================================================================

(defstruct (flash-pool-asset
            (:constructor make-flash-pool-asset)
            (:copier copy-flash-pool-asset))
  "Represents an asset available for flash loans in a pool."
  (address nil :type (or null string))
  (symbol "" :type string)
  (decimals 18 :type integer)
  (available-liquidity 0 :type integer)
  (total-borrowed 0 :type integer)
  (total-fees 0 :type integer)
  (fee-rate +default-flash-fee+ :type integer)
  (borrow-cap 0 :type integer)
  (is-enabled t :type boolean)
  (oracle-address nil :type (or null string))
  (last-borrow-time 0 :type integer))

;;; ============================================================================
;;; Pool Configuration Type
;;; ============================================================================

(defstruct (flash-pool-config
            (:constructor make-flash-pool-config)
            (:copier copy-flash-pool-config))
  "Configuration for a flash loan pool."
  (default-fee-rate +default-flash-fee+ :type integer)
  (protocol-fee-share +protocol-fee-share+ :type integer)
  (max-assets-per-loan +max-flash-loan-assets+ :type integer)
  (max-amount-per-asset +max-flash-loan-amount+ :type integer)
  (require-whitelist nil :type boolean)
  (rate-limit-enabled nil :type boolean)
  (rate-limit-window +rate-limit-window+ :type integer)
  (rate-limit-max-loans +max-loans-per-window+ :type integer)
  (cooldown-enabled nil :type boolean)
  (cooldown-period +cooldown-period+ :type integer))

;;; ============================================================================
;;; Flash Loan Pool Type
;;; ============================================================================

(defstruct (flash-loan-pool
            (:constructor %make-flash-loan-pool)
            (:copier copy-flash-loan-pool))
  "Represents a flash loan liquidity pool.

   A flash loan pool aggregates liquidity for multiple assets and
   provides flash loan functionality with configurable fees and limits."
  (id nil :type (or null string))
  (name "" :type string)
  (protocol "CLPIC" :type string)
  (assets (make-hash-table :test 'equal))
  (reserves 0 :type integer)
  (total-borrowed 0 :type integer)
  (total-fees-collected 0 :type integer)
  (fee-rate +default-flash-fee+ :type integer)
  (protocol-fee-rate +protocol-fee-share+ :type integer)
  (is-active t :type boolean)
  (is-paused nil :type boolean)
  (authorized-borrowers (make-hash-table :test 'equal))
  (borrower-limits (make-hash-table :test 'equal))
  (asset-limits (make-hash-table :test 'equal))
  (whitelist-only nil :type boolean)
  (config nil)
  (created-at 0 :type integer)
  (last-update 0 :type integer))

(defun make-flash-loan-pool (&key id name (protocol "CLPIC")
                                    (fee-rate +default-flash-fee+)
                                    (protocol-fee-rate +protocol-fee-share+)
                                    (is-active t)
                                    (whitelist-only nil)
                                    config)
  "Create a new flash loan pool."
  (let ((now (flash-get-timestamp)))
    (%make-flash-loan-pool
     :id (or id (generate-pool-id protocol now))
     :name (or name (format nil "~A Flash Pool" protocol))
     :protocol protocol
     :assets (make-hash-table :test 'equal)
     :reserves 0
     :total-borrowed 0
     :total-fees-collected 0
     :fee-rate fee-rate
     :protocol-fee-rate protocol-fee-rate
     :is-active is-active
     :is-paused nil
     :authorized-borrowers (make-hash-table :test 'equal)
     :borrower-limits (make-hash-table :test 'equal)
     :asset-limits (make-hash-table :test 'equal)
     :whitelist-only whitelist-only
     :config (or config (make-flash-pool-config))
     :created-at now
     :last-update now)))

;;; ============================================================================
;;; Pool Registry Operations
;;; ============================================================================

(defun create-flash-pool (&key id name protocol fee-rate config)
  "Create and register a new flash loan pool.

   Parameters:
   - id: Pool ID (generated if nil)
   - name: Pool name
   - protocol: Protocol name
   - fee-rate: Fee rate in basis points
   - config: Pool configuration

   Returns: The created pool"
  (let ((pool (make-flash-loan-pool
               :id id
               :name name
               :protocol (or protocol "CLPIC")
               :fee-rate (or fee-rate +default-flash-fee+)
               :config config)))
    (setf (gethash (flash-loan-pool-id pool) *flash-pool-registry*) pool)
    pool))

(defun get-flash-pool (pool-id)
  "Get a flash loan pool by ID.

   Parameters:
   - pool-id: Pool identifier

   Returns: flash-loan-pool or NIL"
  (gethash pool-id *flash-pool-registry*))

(defun list-flash-pools ()
  "List all registered flash loan pools.

   Returns: List of flash-loan-pool structures"
  (let ((pools nil))
    (maphash (lambda (k v)
               (declare (ignore k))
               (push v pools))
             *flash-pool-registry*)
    pools))

(defun delete-flash-pool (pool-id)
  "Remove a flash loan pool from the registry.

   Parameters:
   - pool-id: Pool identifier

   Returns: T if removed, NIL if not found"
  (remhash pool-id *flash-pool-registry*))

;;; ============================================================================
;;; Pool Asset Management
;;; ============================================================================

(defun add-pool-asset (pool address &key symbol (decimals 18)
                                          (liquidity 0)
                                          (fee-rate nil)
                                          (borrow-cap 0)
                                          oracle-address)
  "Add an asset to a flash loan pool.

   Parameters:
   - pool: flash-loan-pool structure
   - address: Asset contract address
   - symbol: Asset symbol
   - decimals: Token decimals
   - liquidity: Initial liquidity
   - fee-rate: Asset-specific fee rate (uses pool default if nil)
   - borrow-cap: Maximum borrowable amount (0 = unlimited)
   - oracle-address: Price oracle address

   Returns: The created flash-pool-asset"
  (unless pool
    (error 'pool-not-found-error
           :pool-id nil
           :message "Pool is required"))

  (let ((asset (make-flash-pool-asset
                :address address
                :symbol (or symbol "")
                :decimals decimals
                :available-liquidity liquidity
                :total-borrowed 0
                :total-fees 0
                :fee-rate (or fee-rate (flash-loan-pool-fee-rate pool))
                :borrow-cap borrow-cap
                :is-enabled t
                :oracle-address oracle-address
                :last-borrow-time 0)))
    (setf (gethash address (flash-loan-pool-assets pool)) asset)
    (incf (flash-loan-pool-reserves pool) liquidity)
    (setf (flash-loan-pool-last-update pool) (flash-get-timestamp))
    asset))

(defun remove-pool-asset (pool address)
  "Remove an asset from a flash loan pool.

   Parameters:
   - pool: flash-loan-pool structure
   - address: Asset contract address

   Returns: T if removed, NIL if not found"
  (unless pool
    (error 'pool-not-found-error
           :pool-id nil
           :message "Pool is required"))

  (let ((asset (gethash address (flash-loan-pool-assets pool))))
    (when asset
      (decf (flash-loan-pool-reserves pool)
            (flash-pool-asset-available-liquidity asset))
      (remhash address (flash-loan-pool-assets pool))
      (setf (flash-loan-pool-last-update pool) (flash-get-timestamp))
      t)))

(defun get-pool-asset (pool address)
  "Get an asset from a pool.

   Parameters:
   - pool: flash-loan-pool structure
   - address: Asset contract address

   Returns: flash-pool-asset or NIL"
  (when pool
    (gethash address (flash-loan-pool-assets pool))))

(defun list-pool-assets (pool)
  "List all assets in a pool.

   Parameters:
   - pool: flash-loan-pool structure

   Returns: List of flash-pool-asset structures"
  (when pool
    (let ((assets nil))
      (maphash (lambda (k v)
                 (declare (ignore k))
                 (push v assets))
               (flash-loan-pool-assets pool))
      assets)))

;;; ============================================================================
;;; Pool Liquidity Management
;;; ============================================================================

(defun get-pool-liquidity (pool &optional asset-address)
  "Get liquidity available in a pool.

   Parameters:
   - pool: flash-loan-pool structure
   - asset-address: Optional specific asset address

   Returns: Total liquidity (integer) or asset-specific liquidity"
  (unless pool
    (return-from get-pool-liquidity 0))

  (if asset-address
      (let ((asset (get-pool-asset pool asset-address)))
        (if asset
            (flash-pool-asset-available-liquidity asset)
            0))
      (flash-loan-pool-reserves pool)))

(defun add-liquidity (pool asset-address amount)
  "Add liquidity to a pool asset.

   Parameters:
   - pool: flash-loan-pool structure
   - asset-address: Asset to add liquidity for
   - amount: Amount to add

   Returns: New total liquidity for the asset"
  (unless pool
    (error 'pool-not-found-error
           :pool-id nil
           :message "Pool is required"))

  (let ((asset (get-pool-asset pool asset-address)))
    (unless asset
      (error 'invalid-asset-error
             :asset asset-address
             :message "Asset not found in pool"))

    (incf (flash-pool-asset-available-liquidity asset) amount)
    (incf (flash-loan-pool-reserves pool) amount)
    (setf (flash-loan-pool-last-update pool) (flash-get-timestamp))
    (flash-pool-asset-available-liquidity asset)))

(defun remove-liquidity (pool asset-address amount)
  "Remove liquidity from a pool asset.

   Parameters:
   - pool: flash-loan-pool structure
   - asset-address: Asset to remove liquidity from
   - amount: Amount to remove

   Returns: New total liquidity for the asset"
  (unless pool
    (error 'pool-not-found-error
           :pool-id nil
           :message "Pool is required"))

  (let ((asset (get-pool-asset pool asset-address)))
    (unless asset
      (error 'invalid-asset-error
             :asset asset-address
             :message "Asset not found in pool"))

    (when (> amount (flash-pool-asset-available-liquidity asset))
      (error 'insufficient-liquidity-error
             :asset asset-address
             :requested amount
             :available (flash-pool-asset-available-liquidity asset)
             :message "Insufficient liquidity to remove"))

    (decf (flash-pool-asset-available-liquidity asset) amount)
    (decf (flash-loan-pool-reserves pool) amount)
    (setf (flash-loan-pool-last-update pool) (flash-get-timestamp))
    (flash-pool-asset-available-liquidity asset)))

;;; ============================================================================
;;; Pool State Management
;;; ============================================================================

(defun pause-flash-pool (pool)
  "Pause a flash loan pool.

   Parameters:
   - pool: flash-loan-pool structure

   Returns: T"
  (unless pool
    (error 'pool-not-found-error
           :pool-id nil
           :message "Pool is required"))

  (setf (flash-loan-pool-is-paused pool) t)
  (setf (flash-loan-pool-last-update pool) (flash-get-timestamp))
  t)

(defun unpause-flash-pool (pool)
  "Unpause a flash loan pool.

   Parameters:
   - pool: flash-loan-pool structure

   Returns: T"
  (unless pool
    (error 'pool-not-found-error
           :pool-id nil
           :message "Pool is required"))

  (setf (flash-loan-pool-is-paused pool) nil)
  (setf (flash-loan-pool-last-update pool) (flash-get-timestamp))
  t)

(defun enable-pool-asset (pool asset-address)
  "Enable an asset for flash loans.

   Parameters:
   - pool: flash-loan-pool structure
   - asset-address: Asset to enable

   Returns: T"
  (let ((asset (get-pool-asset pool asset-address)))
    (unless asset
      (error 'invalid-asset-error
             :asset asset-address
             :message "Asset not found in pool"))
    (setf (flash-pool-asset-is-enabled asset) t)
    t))

(defun disable-pool-asset (pool asset-address)
  "Disable an asset for flash loans.

   Parameters:
   - pool: flash-loan-pool structure
   - asset-address: Asset to disable

   Returns: T"
  (let ((asset (get-pool-asset pool asset-address)))
    (unless asset
      (error 'invalid-asset-error
             :asset asset-address
             :message "Asset not found in pool"))
    (setf (flash-pool-asset-is-enabled asset) nil)
    t))

;;; ============================================================================
;;; Pool Statistics
;;; ============================================================================

(defun get-pool-stats (pool)
  "Get statistics for a pool.

   Parameters:
   - pool: flash-loan-pool structure

   Returns: Association list of stats"
  (unless pool
    (return-from get-pool-stats nil))

  `((:id . ,(flash-loan-pool-id pool))
    (:name . ,(flash-loan-pool-name pool))
    (:protocol . ,(flash-loan-pool-protocol pool))
    (:total-reserves . ,(flash-loan-pool-reserves pool))
    (:total-borrowed . ,(flash-loan-pool-total-borrowed pool))
    (:total-fees . ,(flash-loan-pool-total-fees-collected pool))
    (:fee-rate . ,(/ (flash-loan-pool-fee-rate pool) 100.0))
    (:asset-count . ,(hash-table-count (flash-loan-pool-assets pool)))
    (:is-active . ,(flash-loan-pool-is-active pool))
    (:is-paused . ,(flash-loan-pool-is-paused pool))
    (:whitelist-only . ,(flash-loan-pool-whitelist-only pool))
    (:created-at . ,(flash-loan-pool-created-at pool))
    (:last-update . ,(flash-loan-pool-last-update pool))))

(defun get-pool-utilization (pool &optional asset-address)
  "Get utilization rate for a pool or specific asset.

   Parameters:
   - pool: flash-loan-pool structure
   - asset-address: Optional specific asset

   Returns: Utilization rate as a ratio (0.0 to 1.0)"
  (unless pool
    (return-from get-pool-utilization 0.0))

  (if asset-address
      (let ((asset (get-pool-asset pool asset-address)))
        (if (and asset (> (flash-pool-asset-available-liquidity asset) 0))
            (/ (flash-pool-asset-total-borrowed asset)
               (+ (flash-pool-asset-available-liquidity asset)
                  (flash-pool-asset-total-borrowed asset)))
            0.0))
      (if (> (flash-loan-pool-reserves pool) 0)
          (/ (flash-loan-pool-total-borrowed pool)
             (+ (flash-loan-pool-reserves pool)
                (flash-loan-pool-total-borrowed pool)))
          0.0)))

;;; ============================================================================
;;; Pool Validation
;;; ============================================================================

(defun validate-pool-for-loan (pool assets amounts)
  "Validate that a pool can handle a flash loan request.

   Parameters:
   - pool: flash-loan-pool structure
   - assets: List of asset addresses to borrow
   - amounts: List of amounts to borrow

   Returns: T if valid, signals error otherwise"
  (unless pool
    (error 'pool-not-found-error
           :pool-id nil
           :message "Pool is required"))

  (unless (flash-loan-pool-is-active pool)
    (error 'pool-paused-error
           :pool-id (flash-loan-pool-id pool)
           :message "Pool is not active"))

  (when (flash-loan-pool-is-paused pool)
    (error 'pool-paused-error
           :pool-id (flash-loan-pool-id pool)
           :message "Pool is paused"))

  ;; Check each asset
  (loop for asset-addr in assets
        for amount in amounts
        do (let ((asset (get-pool-asset pool asset-addr)))
             (unless asset
               (error 'invalid-asset-error
                      :asset asset-addr
                      :message "Asset not available in pool"))

             (unless (flash-pool-asset-is-enabled asset)
               (error 'invalid-asset-error
                      :asset asset-addr
                      :message "Asset is disabled"))

             (when (> amount (flash-pool-asset-available-liquidity asset))
               (error 'insufficient-liquidity-error
                      :asset asset-addr
                      :requested amount
                      :available (flash-pool-asset-available-liquidity asset)
                      :message "Insufficient liquidity"))

             (when (and (> (flash-pool-asset-borrow-cap asset) 0)
                        (> amount (flash-pool-asset-borrow-cap asset)))
               (error 'limit-exceeded-error
                      :limit-type :borrow-cap
                      :limit-value (flash-pool-asset-borrow-cap asset)
                      :requested amount
                      :message "Borrow cap exceeded"))))
  t)
