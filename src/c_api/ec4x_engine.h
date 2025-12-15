/**
 * EC4X Game Engine C API
 *
 * Exposes core game engine and AI functionality for parallel orchestration.
 * Thread safety: AI order generation is thread-safe with copied state.
 *                Turn resolution must be called sequentially.
 */

#ifndef EC4X_ENGINE_H
#define EC4X_ENGINE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handles
typedef void* EC4XGame;
typedef void* EC4XOrders;
typedef void* EC4XFilteredState;

// =============================================================================
// Library Initialization
// =============================================================================

/**
 * Initialize Nim runtime (MUST be called once from main thread before any other calls)
 * @return 0 on success, -1 on failure
 */
int ec4x_init_runtime(void);

// =============================================================================
// Game Lifecycle
// =============================================================================

/**
 * Initialize a new game with AI players
 * @param num_players Number of AI players (2-12)
 * @param seed Random seed for map generation
 * @param map_rings Number of hex rings for star map (1-5)
 * @param max_turns Maximum turn limit
 * @return Game handle, or NULL on failure
 */
EC4XGame ec4x_init_game(int num_players, int64_t seed, int map_rings, int max_turns);

/**
 * Clean up and destroy game state
 * @param game Game handle to destroy
 */
void ec4x_destroy_game(EC4XGame game);

// =============================================================================
// Fog-of-War State (for AI)
// =============================================================================

/**
 * Create a filtered view of game state for a specific house (fog-of-war)
 * This creates a copy that can be safely used in parallel threads
 * @param game Game handle
 * @param house_id House ID (0-based index)
 * @return Filtered state handle, must be freed with ec4x_destroy_filtered_state
 */
EC4XFilteredState ec4x_create_filtered_state(EC4XGame game, int house_id);

/**
 * Free a filtered state
 * @param state Filtered state handle
 */
void ec4x_destroy_filtered_state(EC4XFilteredState state);

// =============================================================================
// AI Operations (Thread-Safe with Filtered State)
// =============================================================================

/**
 * Generate AI orders for a specific house (thread-safe)
 * Uses the provided filtered state and RNG seed for deterministic generation
 * @param filtered_state Filtered game state for this house
 * @param house_id House ID (0-based index)
 * @param rng_seed Random seed for this AI's decision making
 * @return Orders handle, must be freed with ec4x_destroy_orders
 */
EC4XOrders ec4x_generate_ai_orders(EC4XFilteredState filtered_state,
                                    int house_id,
                                    int64_t rng_seed);

/**
 * Free orders handle
 * @param orders Orders handle to free
 */
void ec4x_destroy_orders(EC4XOrders orders);

// =============================================================================
// Turn Resolution (NOT Thread-Safe - Sequential Only)
// =============================================================================

/**
 * Execute zero-turn commands from AI orders
 * Must be called BEFORE ec4x_resolve_turn, and MUST be sequential
 * Zero-turn commands modify game state immediately (cargo transfers, etc.)
 * @param game Game handle
 * @param orders Orders handle containing zero-turn commands
 * @return 0 on success, negative on error
 */
int ec4x_execute_zero_turn_commands(EC4XGame game, EC4XOrders orders);

/**
 * Resolve a game turn with orders from all houses
 * This modifies game state and MUST be called sequentially
 * Call AFTER executing all zero-turn commands
 * @param game Game handle
 * @param orders Array of order handles (one per house)
 * @param num_orders Number of orders (must equal num_players)
 * @return 0 on success, negative on error
 */
int ec4x_resolve_turn(EC4XGame game, EC4XOrders* orders, int num_orders);

// =============================================================================
// Game State Queries
// =============================================================================

/**
 * Get current turn number
 * @param game Game handle
 * @return Current turn (1-based)
 */
int ec4x_get_turn(EC4XGame game);

/**
 * Check if game has ended (victory or turn limit)
 * @param game Game handle
 * @return true if game ended
 */
bool ec4x_check_victory(EC4XGame game);

/**
 * Get victor house ID (-1 if no victor yet)
 * @param game Game handle
 * @return House ID of victor, or -1
 */
int ec4x_get_victor(EC4XGame game);

// =============================================================================
// Diagnostics & Database
// =============================================================================

/**
 * Collect fleet snapshots for current turn (stored in memory)
 * Should be called every turn alongside ec4x_collect_diagnostics
 * @param game Game handle
 * @param turn Current turn number
 * @return 0 on success, negative on error
 */
int ec4x_collect_fleet_snapshots(EC4XGame game, int turn);

/**
 * Collect diagnostics for current turn (all houses)
 * Stores in internal buffer for batch DB write at end
 * @param game Game handle
 * @param turn Current turn number
 * @return 0 on success, negative on error
 */
int ec4x_collect_diagnostics(EC4XGame game, int turn);

/**
 * Write all collected diagnostics to SQLite database
 * Should be called once after game completes
 * @param game Game handle
 * @param db_path Path to SQLite database file
 * @return 0 on success, negative on error
 */
int ec4x_write_diagnostics_db(EC4XGame game, const char* db_path);

/**
 * Write diagnostics to CSV file (legacy format)
 * @param game Game handle
 * @param csv_path Path to CSV file
 * @return 0 on success, negative on error
 */
int ec4x_write_diagnostics_csv(EC4XGame game, const char* csv_path);

// =============================================================================
// Error Handling
// =============================================================================

/**
 * Get last error message
 * @return Error string, or NULL if no error
 */
const char* ec4x_get_last_error(void);

#ifdef __cplusplus
}
#endif

#endif // EC4X_ENGINE_H
