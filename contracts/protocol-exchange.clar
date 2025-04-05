;; Quantum Protocol Exchange - Advanced Multi-Phase Transaction Framework

;; Administrative constants
(define-constant PROTOCOL_SUPERVISOR tx-sender)
(define-constant ERROR_UNAUTHORIZED (err u100))
(define-constant ERROR_NO_CHANNEL (err u101))
(define-constant ERROR_ALREADY_PROCESSED (err u102))
(define-constant ERROR_TRANSFER_UNSUCCESSFUL (err u103))
(define-constant ERROR_INVALID_IDENTIFIER (err u104))
(define-constant ERROR_INVALID_QUANTITY (err u105))
(define-constant ERROR_INVALID_ORIGIN (err u106))
(define-constant ERROR_CHANNEL_OUTDATED (err u107))
(define-constant CHANNEL_LIFESPAN_BLOCKS u1008)

;; Primary data storage
(define-map ChannelRegistry
  { channel-identifier: uint }
  {
    origin-entity: principal,
    destination-entity: principal,
    symbol-identifier: uint,
    quantity: uint,
    channel-status: (string-ascii 10),
    genesis-block: uint,
    terminus-block: uint
  }
)

;; Channel identifier management
(define-data-var latest-channel-identifier uint u0)

;; Utility functions
(define-private (valid-destination? (destination principal))
  (and 
    (not (is-eq destination tx-sender))
    (not (is-eq destination (as-contract tx-sender)))
  )
)

(define-private (valid-channel-identifier? (channel-identifier uint))
  (<= channel-identifier (var-get latest-channel-identifier))
)

;; Core protocol functions

;; Execute channel transaction
(define-public (execute-channel-transaction (channel-identifier uint))
  (begin
    (asserts! (valid-channel-identifier? channel-identifier) ERROR_INVALID_IDENTIFIER)
    (let
      (
        (channel-data (unwrap! (map-get? ChannelRegistry { channel-identifier: channel-identifier }) ERROR_NO_CHANNEL))
        (destination (get destination-entity channel-data))
        (quantity (get quantity channel-data))
        (symbol (get symbol-identifier channel-data))
      )
      (asserts! (or (is-eq tx-sender PROTOCOL_SUPERVISOR) (is-eq tx-sender (get origin-entity channel-data))) ERROR_UNAUTHORIZED)
      (asserts! (is-eq (get channel-status channel-data) "pending") ERROR_ALREADY_PROCESSED)
      (asserts! (<= block-height (get terminus-block channel-data)) ERROR_CHANNEL_OUTDATED)
      (match (as-contract (stx-transfer? quantity tx-sender destination))
        success
          (begin
            (map-set ChannelRegistry
              { channel-identifier: channel-identifier }
              (merge channel-data { channel-status: "completed" })
            )
            (print {operation: "channel_executed", channel-identifier: channel-identifier, destination: destination, symbol-identifier: symbol, quantity: quantity})
            (ok true)
          )
        error ERROR_TRANSFER_UNSUCCESSFUL
      )
    )
  )
)

;; Terminate pending channel
(define-public (terminate-channel (channel-identifier uint))
  (begin
    (asserts! (valid-channel-identifier? channel-identifier) ERROR_INVALID_IDENTIFIER)
    (let
      (
        (channel-data (unwrap! (map-get? ChannelRegistry { channel-identifier: channel-identifier }) ERROR_NO_CHANNEL))
        (origin (get origin-entity channel-data))
        (quantity (get quantity channel-data))
      )
      (asserts! (is-eq tx-sender origin) ERROR_UNAUTHORIZED)
      (asserts! (is-eq (get channel-status channel-data) "pending") ERROR_ALREADY_PROCESSED)
      (asserts! (<= block-height (get terminus-block channel-data)) ERROR_CHANNEL_OUTDATED)
      (match (as-contract (stx-transfer? quantity tx-sender origin))
        success
          (begin
            (map-set ChannelRegistry
              { channel-identifier: channel-identifier }
              (merge channel-data { channel-status: "terminated" })
            )
            (print {operation: "channel_terminated", channel-identifier: channel-identifier, origin: origin, quantity: quantity})
            (ok true)
          )
        error ERROR_TRANSFER_UNSUCCESSFUL
      )
    )
  )
)

;; Modify channel duration
(define-public (modify-channel-duration (channel-identifier uint) (additional-blocks uint))
  (begin
    (asserts! (valid-channel-identifier? channel-identifier) ERROR_INVALID_IDENTIFIER)
    (asserts! (> additional-blocks u0) ERROR_INVALID_QUANTITY)
    (asserts! (<= additional-blocks u1440) ERROR_INVALID_QUANTITY) ;; Max ~10 days extension
    (let
      (
        (channel-data (unwrap! (map-get? ChannelRegistry { channel-identifier: channel-identifier }) ERROR_NO_CHANNEL))
        (origin (get origin-entity channel-data)) 
        (destination (get destination-entity channel-data))
        (current-terminus (get terminus-block channel-data))
        (updated-terminus (+ current-terminus additional-blocks))
      )
      (asserts! (or (is-eq tx-sender origin) (is-eq tx-sender destination) (is-eq tx-sender PROTOCOL_SUPERVISOR)) ERROR_UNAUTHORIZED)
      (asserts! (or (is-eq (get channel-status channel-data) "pending") (is-eq (get channel-status channel-data) "accepted")) ERROR_ALREADY_PROCESSED)
      (map-set ChannelRegistry
        { channel-identifier: channel-identifier }
        (merge channel-data { terminus-block: updated-terminus })
      )
      (print {operation: "duration_modified", channel-identifier: channel-identifier, requestor: tx-sender, new-terminus-block: updated-terminus})
      (ok true)
    )
  )
)

;; Retrieve expired channel resources
(define-public (retrieve-expired-channel (channel-identifier uint))
  (begin
    (asserts! (valid-channel-identifier? channel-identifier) ERROR_INVALID_IDENTIFIER)
    (let
      (
        (channel-data (unwrap! (map-get? ChannelRegistry { channel-identifier: channel-identifier }) ERROR_NO_CHANNEL))
        (origin (get origin-entity channel-data))
        (quantity (get quantity channel-data))
        (expiration (get terminus-block channel-data))
      )
      (asserts! (or (is-eq tx-sender origin) (is-eq tx-sender PROTOCOL_SUPERVISOR)) ERROR_UNAUTHORIZED)
      (asserts! (or (is-eq (get channel-status channel-data) "pending") (is-eq (get channel-status channel-data) "accepted")) ERROR_ALREADY_PROCESSED)
      (asserts! (> block-height expiration) (err u108)) ;; Must be expired
      (match (as-contract (stx-transfer? quantity tx-sender origin))
        success
          (begin
            (map-set ChannelRegistry
              { channel-identifier: channel-identifier }
              (merge channel-data { channel-status: "expired" })
            )
            (print {operation: "expired_channel_retrieved", channel-identifier: channel-identifier, origin: origin, quantity: quantity})
            (ok true)
          )
        error ERROR_TRANSFER_UNSUCCESSFUL
      )
    )
  )
)
