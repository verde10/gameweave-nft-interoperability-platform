;; gameweave-registry
;; 
;; This contract serves as the central hub of the GameWeave ecosystem, maintaining 
;; a registry of all participating games and the compatibility mappings between their NFTs.
;; Game developers register their games and define which external NFTs they support and 
;; how those NFTs translate into functional items within their game.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-GAME-ALREADY-REGISTERED (err u101))
(define-constant ERR-GAME-NOT-FOUND (err u102))
(define-constant ERR-MAPPING-ALREADY-EXISTS (err u103))
(define-constant ERR-MAPPING-NOT-FOUND (err u104))
(define-constant ERR-INVALID-PARAMETERS (err u105))
(define-constant ERR-NOT-GAME-OWNER (err u106))
(define-constant ERR-INVALID-NFT-CONTRACT (err u107))
(define-constant ERR-NOT-ADMIN (err u108))

;; Data Maps and Variables

;; Contract administrator - can perform administrative functions
(define-data-var contract-admin principal tx-sender)

;; Game registry - maps game IDs to their details
(define-map games
  { game-id: uint }
  {
    name: (string-ascii 64),
    description: (string-utf8 256),
    owner: principal,
    website-url: (string-ascii 128),
    created-at: uint,
    active: bool
  }
)

;; NFT contract registry - stores information about NFT contracts
(define-map nft-contracts
  { contract-id: (string-ascii 128) }
  {
    name: (string-ascii 64),
    contract-principal: principal,
    description: (string-utf8 256),
    created-at: uint
  }
)

;; Compatibility mappings between NFTs and games
(define-map compatibility-mappings
  { 
    source-contract-id: (string-ascii 128),
    target-game-id: uint
  }
  {
    translation-rules: (string-utf8 1024), ;; JSON string containing translation rules
    approved: bool,
    created-at: uint,
    updated-at: uint
  }
)

;; Keeps track of the next available game ID
(define-data-var next-game-id uint u1)

;; Private functions

;; Check if the sender is the contract administrator
(define-private (is-admin)
  (is-eq tx-sender (var-get contract-admin))
)

;; Check if the sender is the owner of a specific game
(define-private (is-game-owner (game-id uint))
  (match (map-get? games { game-id: game-id })
    game (is-eq tx-sender (get owner game))
    false
  )
)

;; Get the current block height as a timestamp
(define-private (get-current-time)
  block-height
)

;; Read-only functions

;; Get game details by ID
(define-read-only (get-game (game-id uint))
  (map-get? games { game-id: game-id })
)

;; Get NFT contract details by contract ID
(define-read-only (get-nft-contract (contract-id (string-ascii 128)))
  (map-get? nft-contracts { contract-id: contract-id })
)

;; Check if a game exists
(define-read-only (game-exists (game-id uint))
  (is-some (map-get? games { game-id: game-id }))
)

;; Get compatibility mapping between an NFT contract and a game
(define-read-only (get-compatibility-mapping
    (source-contract-id (string-ascii 128))
    (target-game-id uint))
  (map-get? compatibility-mappings 
    { 
      source-contract-id: source-contract-id,
      target-game-id: target-game-id
    }
  )
)

;; Check if a compatibility mapping exists
(define-read-only (mapping-exists
    (source-contract-id (string-ascii 128))
    (target-game-id uint))
  (is-some 
    (map-get? compatibility-mappings 
      { 
        source-contract-id: source-contract-id,
        target-game-id: target-game-id
      }
    )
  )
)

;; Get all compatibility mappings for a game (limited to returning bool for existence)
(define-read-only (has-game-mappings (game-id uint))
  (and 
    (game-exists game-id)
    (> game-id u0)
  )
)

;; Public functions

;; Change the contract administrator
(define-public (set-admin (new-admin principal))
  (begin
    (asserts! (is-admin) ERR-NOT-AUTHORIZED)
    (ok (var-set contract-admin new-admin))
  )
)

;; Register a new game
(define-public (register-game
    (name (string-ascii 64))
    (description (string-utf8 256))
    (website-url (string-ascii 128)))
  (let
    (
      (game-id (var-get next-game-id))
      (current-time (get-current-time))
    )
    (asserts! (> (len name) u0) ERR-INVALID-PARAMETERS)
    (asserts! (> (len description) u0) ERR-INVALID-PARAMETERS)
    
    ;; Insert the new game data
    (map-set games
      { game-id: game-id }
      {
        name: name,
        description: description,
        owner: tx-sender,
        website-url: website-url,
        created-at: current-time,
        active: true
      }
    )
    
    ;; Increment the game ID counter
    (var-set next-game-id (+ game-id u1))
    
    (ok game-id)
  )
)

;; Update game details
(define-public (update-game
    (game-id uint)
    (name (string-ascii 64))
    (description (string-utf8 256))
    (website-url (string-ascii 128))
    (active bool))
  (begin
    (asserts! (is-game-owner game-id) ERR-NOT-GAME-OWNER)
    (asserts! (game-exists game-id) ERR-GAME-NOT-FOUND)
    (asserts! (> (len name) u0) ERR-INVALID-PARAMETERS)
    (asserts! (> (len description) u0) ERR-INVALID-PARAMETERS)
    
    (map-set games
      { game-id: game-id }
      {
        name: name,
        description: description,
        owner: tx-sender, ;; Maintain the same owner
        website-url: website-url,
        created-at: (get created-at (unwrap! (get-game game-id) ERR-GAME-NOT-FOUND)),
        active: active
      }
    )
    
    (ok true)
  )
)

;; Transfer game ownership
(define-public (transfer-game-ownership
    (game-id uint)
    (new-owner principal))
  (let
    (
      (game (unwrap! (get-game game-id) ERR-GAME-NOT-FOUND))
    )
    (asserts! (is-game-owner game-id) ERR-NOT-GAME-OWNER)
    
    (map-set games
      { game-id: game-id }
      (merge game { owner: new-owner })
    )
    
    (ok true)
  )
)

;; Register an NFT contract
(define-public (register-nft-contract
    (contract-id (string-ascii 128))
    (name (string-ascii 64))
    (contract-principal principal)
    (description (string-utf8 256)))
  (let
    (
      (current-time (get-current-time))
    )
    (asserts! (is-admin) ERR-NOT-ADMIN)
    (asserts! (> (len contract-id) u0) ERR-INVALID-PARAMETERS)
    (asserts! (> (len name) u0) ERR-INVALID-PARAMETERS)
    (asserts! (is-none (get-nft-contract contract-id)) ERR-INVALID-NFT-CONTRACT)
    
    (map-set nft-contracts
      { contract-id: contract-id }
      {
        name: name,
        contract-principal: contract-principal,
        description: description,
        created-at: current-time
      }
    )
    
    (ok true)
  )
)

;; Create a new NFT compatibility mapping
(define-public (create-compatibility-mapping
    (source-contract-id (string-ascii 128))
    (target-game-id uint)
    (translation-rules (string-utf8 1024)))
  (let
    (
      (current-time (get-current-time))
    )
    (asserts! (is-game-owner target-game-id) ERR-NOT-GAME-OWNER)
    (asserts! (game-exists target-game-id) ERR-GAME-NOT-FOUND)
    (asserts! (is-some (get-nft-contract source-contract-id)) ERR-INVALID-NFT-CONTRACT)
    (asserts! (not (mapping-exists source-contract-id target-game-id)) ERR-MAPPING-ALREADY-EXISTS)
    (asserts! (> (len translation-rules) u0) ERR-INVALID-PARAMETERS)
    
    (map-set compatibility-mappings
      { 
        source-contract-id: source-contract-id,
        target-game-id: target-game-id
      }
      {
        translation-rules: translation-rules,
        approved: false, ;; Mappings start as unapproved
        created-at: current-time,
        updated-at: current-time
      }
    )
    
    (ok true)
  )
)

;; Update an existing compatibility mapping
(define-public (update-compatibility-mapping
    (source-contract-id (string-ascii 128))
    (target-game-id uint)
    (translation-rules (string-utf8 1024)))
  (let
    (
      (current-time (get-current-time))
      (existing-mapping (unwrap! (get-compatibility-mapping source-contract-id target-game-id) ERR-MAPPING-NOT-FOUND))
    )
    (asserts! (is-game-owner target-game-id) ERR-NOT-GAME-OWNER)
    (asserts! (> (len translation-rules) u0) ERR-INVALID-PARAMETERS)
    
    (map-set compatibility-mappings
      { 
        source-contract-id: source-contract-id,
        target-game-id: target-game-id
      }
      (merge existing-mapping 
        {
          translation-rules: translation-rules,
          approved: false, ;; Updates reset approval status
          updated-at: current-time
        }
      )
    )
    
    (ok true)
  )
)

;; Approve or reject a compatibility mapping
(define-public (set-mapping-approval
    (source-contract-id (string-ascii 128))
    (target-game-id uint)
    (approved bool))
  (let
    (
      (current-time (get-current-time))
      (existing-mapping (unwrap! (get-compatibility-mapping source-contract-id target-game-id) ERR-MAPPING-NOT-FOUND))
    )
    (asserts! (is-admin) ERR-NOT-ADMIN)
    
    (map-set compatibility-mappings
      { 
        source-contract-id: source-contract-id,
        target-game-id: target-game-id
      }
      (merge existing-mapping 
        {
          approved: approved,
          updated-at: current-time
        }
      )
    )
    
    (ok true)
  )
)

;; Delete a compatibility mapping
(define-public (delete-compatibility-mapping
    (source-contract-id (string-ascii 128))
    (target-game-id uint))
  (begin
    (asserts! (or (is-game-owner target-game-id) (is-admin)) ERR-NOT-AUTHORIZED)
    (asserts! (mapping-exists source-contract-id target-game-id) ERR-MAPPING-NOT-FOUND)
    
    (map-delete compatibility-mappings
      { 
        source-contract-id: source-contract-id,
        target-game-id: target-game-id
      }
    )
    
    (ok true)
  )
)