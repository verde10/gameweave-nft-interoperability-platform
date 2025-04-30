;; gameweave-passport
;; This contract creates and manages player "passports" that record which games a player 
;; has participated in and how their NFTs have been used across the GameWeave ecosystem.
;; The passport serves as a unified gaming identity, tracking achievements, asset migrations,
;; and usage history across different game environments.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PASSPORT-EXISTS (err u101))
(define-constant ERR-PASSPORT-NOT-FOUND (err u102))
(define-constant ERR-GAME-NOT-REGISTERED (err u103))
(define-constant ERR-INVALID-NFT (err u104))
(define-constant ERR-ALREADY-REGISTERED (err u105))
(define-constant ERR-GAME-NOT-AUTHORIZED (err u106))
(define-constant ERR-INTERACTION-NOT-FOUND (err u107))

;; Data definitions

;; Admin management
(define-data-var contract-owner principal tx-sender)

;; Registered games map: tracks authorized games that can interact with the passport system
;; Key: game-id (string), Value: principal (contract address of the game)
(define-map registered-games (string-ascii 50) principal)

;; Player Passports map: stores each player's passport information
;; Key: player principal, Value: boolean indicating if passport exists
(define-map player-passports principal bool)

;; Passport Game Interactions: tracks which games a player has interacted with
;; Key: [player, game-id], Value: first-interaction-block-height
(define-map passport-game-interactions {player: principal, game-id: (string-ascii 50)} uint)

;; NFT Usage History: records how NFTs are used across games
;; Key: [player, nft-id, source-game, target-game], Value: usage details
(define-map nft-usage-history 
  {
    player: principal, 
    nft-id: (string-ascii 50), 
    source-game: (string-ascii 50), 
    target-game: (string-ascii 50)
  } 
  {
    first-used: uint,
    last-used: uint,
    use-count: uint
  }
)

;; Private functions

;; Check if a player has a passport
(define-private (has-passport (player principal))
  (default-to false (map-get? player-passports player))
)

;; Check if a game is registered in the system
(define-private (is-game-registered (game-id (string-ascii 50)))
  (is-some (map-get? registered-games game-id))
)

;; Check if tx-sender is the owner of this contract
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

;; Check if tx-sender is an authorized game
(define-private (is-authorized-game (game-id (string-ascii 50)))
  (match (map-get? registered-games game-id)
    game-principal (is-eq tx-sender game-principal)
    false
  )
)

;; Read-only functions

;; Check if a player has a passport
(define-read-only (player-has-passport (player principal))
  (has-passport player)
)

;; Get the list of games a player has interacted with
;; Note: Clarity doesn't support returning dynamic lists, so front-end will need to query 
;; individual game interactions
(define-read-only (check-game-interaction (player principal) (game-id (string-ascii 50)))
  (map-get? passport-game-interactions {player: player, game-id: game-id})
)

;; Check if an NFT has been used across games
(define-read-only (get-nft-usage-history 
  (player principal) 
  (nft-id (string-ascii 50)) 
  (source-game (string-ascii 50)) 
  (target-game (string-ascii 50)))
  (map-get? nft-usage-history {
    player: player,
    nft-id: nft-id,
    source-game: source-game,
    target-game: target-game
  })
)

;; Get the number of games a player has interacted with
;; Note: This is approximated by a client querying individual interactions
;; since Clarity cannot return the size of a composite key map

;; Public functions

;; Create a new passport for a player
;; Can only be called by the player themselves
(define-public (create-passport)
  (let ((player tx-sender))
    (asserts! (not (has-passport player)) ERR-PASSPORT-EXISTS)
    (map-set player-passports player true)
    (ok true)
  )
)

;; Register a new game to the GameWeave ecosystem
;; Can only be called by the contract owner
(define-public (register-game (game-id (string-ascii 50)) (game-principal principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-game-registered game-id)) ERR-ALREADY-REGISTERED)
    (map-set registered-games game-id game-principal)
    (ok true)
  )
)

;; Record a player interaction with a game
;; Can only be called by the registered game contract
(define-public (record-game-interaction (player principal) (game-id (string-ascii 50)))
  (begin
    (asserts! (is-authorized-game game-id) ERR-GAME-NOT-AUTHORIZED)
    (asserts! (has-passport player) ERR-PASSPORT-NOT-FOUND)
    
    ;; If first interaction with this game, record it
    (if (is-none (map-get? passport-game-interactions {player: player, game-id: game-id}))
      (map-set passport-game-interactions {player: player, game-id: game-id} block-height)
      true
    )
    (ok true)
  )
)

;; Record the usage of an NFT from one game in another game
;; Can only be called by the target game contract
(define-public (record-nft-usage 
  (player principal) 
  (nft-id (string-ascii 50)) 
  (source-game (string-ascii 50)) 
  (target-game (string-ascii 50)))
  (begin
    (asserts! (is-authorized-game target-game) ERR-GAME-NOT-AUTHORIZED)
    (asserts! (is-game-registered source-game) ERR-GAME-NOT-REGISTERED)
    (asserts! (has-passport player) ERR-PASSPORT-NOT-FOUND)
    
    ;; Update or create NFT usage record
    (match (map-get? nft-usage-history {
      player: player,
      nft-id: nft-id,
      source-game: source-game,
      target-game: target-game
    })
      existing-record (map-set nft-usage-history 
        {
          player: player,
          nft-id: nft-id,
          source-game: source-game,
          target-game: target-game
        }
        {
          first-used: (get first-used existing-record),
          last-used: block-height,
          use-count: (+ (get use-count existing-record) u1)
        }
      )
      ;; First time this NFT is used between these games
      (map-set nft-usage-history 
        {
          player: player,
          nft-id: nft-id,
          source-game: source-game,
          target-game: target-game
        }
        {
          first-used: block-height,
          last-used: block-height,
          use-count: u1
        }
      )
    )
    (ok true)
  )
)

;; Change contract ownership
;; Can only be called by the current contract owner
(define-public (transfer-contract-ownership (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)