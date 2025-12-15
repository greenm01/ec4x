/**
 * EC4X Parallel Simulation Orchestrator
 *
 * Runs game simulation with parallel AI order generation using pthreads.
 * Achieves ~3x speedup over sequential by parallelizing 4 AI players.
 */

#include "ec4x_engine.h"
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>

// Nim runtime stubs (required for static linking with --noMain)
// The Nim library references these but we provide our own main()
int cmdCount = 0;
char** cmdLine = NULL;

// Configuration
#define MAX_PLAYERS 12
#define DEFAULT_TURNS 200
#define DEFAULT_SEED 42
#define DEFAULT_RINGS 4  // 4 rings = ~48 systems, good for up to 12 players

// Thread argument for parallel AI order generation
typedef struct {
    EC4XFilteredState filtered_state;
    int house_id;
    int64_t rng_seed;
    EC4XOrders result;  // Output
    int status;         // 0 = success, negative = error
} AIThreadArg;

// =============================================================================
// Timing Utilities
// =============================================================================

double get_time_ms() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0;
}

// =============================================================================
// Parallel AI Order Generation
// =============================================================================

void* ai_worker_thread(void* arg) {
    AIThreadArg* thread_arg = (AIThreadArg*)arg;

    // Generate orders using filtered state (thread-safe)
    thread_arg->result = ec4x_generate_ai_orders(
        thread_arg->filtered_state,
        thread_arg->house_id,
        thread_arg->rng_seed
    );

    if (thread_arg->result == NULL) {
        fprintf(stderr, "Error generating AI orders for house %d: %s\n",
                thread_arg->house_id, ec4x_get_last_error());
        thread_arg->status = -1;
    } else {
        thread_arg->status = 0;
    }

    return NULL;
}

int generate_orders_parallel(EC4XGame game, int num_players, int64_t base_seed,
                              EC4XOrders* orders_out) {
    pthread_t threads[MAX_PLAYERS];
    AIThreadArg thread_args[MAX_PLAYERS];
    double t_start, t_end;

    // Phase 1: Create filtered states (sequential, fast)
    t_start = get_time_ms();
    for (int i = 0; i < num_players; i++) {
        thread_args[i].filtered_state = ec4x_create_filtered_state(game, i);
        if (thread_args[i].filtered_state == NULL) {
            fprintf(stderr, "Failed to create filtered state for house %d\n", i);
            // Cleanup
            for (int j = 0; j < i; j++) {
                ec4x_destroy_filtered_state(thread_args[j].filtered_state);
            }
            return -1;
        }
        thread_args[i].house_id = i;
        thread_args[i].rng_seed = base_seed + i;  // Unique seed per house
        thread_args[i].result = NULL;
        thread_args[i].status = 0;
    }
    t_end = get_time_ms();
    double fog_time = t_end - t_start;

    // Phase 2: Generate AI orders in parallel
    t_start = get_time_ms();
    for (int i = 0; i < num_players; i++) {
        if (pthread_create(&threads[i], NULL, ai_worker_thread, &thread_args[i]) != 0) {
            fprintf(stderr, "Failed to create thread for house %d\n", i);
            return -1;
        }
    }

    // Wait for all threads to complete
    for (int i = 0; i < num_players; i++) {
        pthread_join(threads[i], NULL);
    }
    t_end = get_time_ms();
    double ai_time = t_end - t_start;

    // Check for errors and collect results
    int error = 0;
    for (int i = 0; i < num_players; i++) {
        if (thread_args[i].status != 0) {
            error = -1;
        } else {
            orders_out[i] = thread_args[i].result;
        }
        // Clean up filtered state (no longer needed)
        ec4x_destroy_filtered_state(thread_args[i].filtered_state);
    }

    if (error != 0) {
        // Clean up any successful orders
        for (int i = 0; i < num_players; i++) {
            if (thread_args[i].result != NULL) {
                ec4x_destroy_orders(thread_args[i].result);
            }
        }
        return error;
    }

    // Timing info (only shown every 10 turns in main loop)
    // printf("  Fog-of-war: %.1fms, AI parallel: %.1fms\n", fog_time, ai_time);

    return 0;
}

// =============================================================================
// Main Simulation Loop
// =============================================================================

int run_simulation(int num_players, int max_turns, int64_t seed, int map_rings,
                   const char* output_db) {
    printf("=== EC4X Parallel Simulation ===\n");
    printf("Players: %d\n", num_players);
    printf("Max turns: %d\n", max_turns);
    printf("Seed: %ld\n", seed);
    printf("Map rings: %d\n\n", map_rings);

    // Initialize game
    double t_start = get_time_ms();
    EC4XGame game = ec4x_init_game(num_players, seed, map_rings, max_turns);
    if (game == NULL) {
        fprintf(stderr, "Failed to initialize game: %s\n", ec4x_get_last_error());
        return 1;
    }
    double t_end = get_time_ms();
    printf("Game initialized in %.1fms\n\n", t_end - t_start);

    // Profiling accumulators
    double total_fog_time = 0;
    double total_ai_time = 0;
    double total_zero_turn_time = 0;
    double total_resolve_time = 0;
    double total_diagnostics_time = 0;

    // Main simulation loop
    int turn = 1;
    int64_t turn_rng_seed = seed;

    for (turn = 1; turn <= max_turns; turn++) {
        if (turn % 10 == 0) {
            printf("Turn %d/%d...\n", turn, max_turns);
        }

        EC4XOrders orders[MAX_PLAYERS];

        // PARALLEL: Generate AI orders (4 threads)
        t_start = get_time_ms();
        if (generate_orders_parallel(game, num_players, turn_rng_seed, orders) != 0) {
            fprintf(stderr, "Error generating orders on turn %d\n", turn);
            ec4x_destroy_game(game);
            return 1;
        }
        t_end = get_time_ms();
        total_ai_time += (t_end - t_start);

        // SEQUENTIAL: Execute zero-turn commands
        t_start = get_time_ms();
        for (int i = 0; i < num_players; i++) {
            if (ec4x_execute_zero_turn_commands(game, orders[i]) != 0) {
                fprintf(stderr, "Error executing zero-turn commands for house %d on turn %d\n",
                        i, turn);
            }
        }
        t_end = get_time_ms();
        total_zero_turn_time += (t_end - t_start);

        // SEQUENTIAL: Resolve turn
        t_start = get_time_ms();
        if (ec4x_resolve_turn(game, orders, num_players) != 0) {
            fprintf(stderr, "Error resolving turn %d: %s\n", turn, ec4x_get_last_error());
            // Cleanup
            for (int i = 0; i < num_players; i++) {
                ec4x_destroy_orders(orders[i]);
            }
            ec4x_destroy_game(game);
            return 1;
        }
        t_end = get_time_ms();
        total_resolve_time += (t_end - t_start);

        // Clean up orders
        for (int i = 0; i < num_players; i++) {
            ec4x_destroy_orders(orders[i]);
        }

        // Collect diagnostics (in memory)
        t_start = get_time_ms();
        if (ec4x_collect_diagnostics(game, turn) != 0) {
            fprintf(stderr, "Warning: Failed to collect diagnostics for turn %d\n", turn);
        }
        t_end = get_time_ms();
        total_diagnostics_time += (t_end - t_start);

        // Collect fleet snapshots (in memory)
        if (ec4x_collect_fleet_snapshots(game, turn) != 0) {
            fprintf(stderr, "Warning: Failed to collect fleet snapshots for turn %d\n", turn);
        }

        // Check for victory
        if (ec4x_check_victory(game)) {
            int victor = ec4x_get_victor(game);
            printf("\nVictory achieved on turn %d!\n", turn);
            if (victor >= 0) {
                printf("Victor: House %d\n", victor);
            }
            break;
        }

        // Update RNG seed for next turn
        turn_rng_seed = turn_rng_seed * 1103515245 + 12345;
    }

    printf("\nSimulation complete! Ran %d turns\n\n", turn);

    // Write diagnostics to database (batched)
    printf("Writing diagnostics to database...\n");
    t_start = get_time_ms();
    if (ec4x_write_diagnostics_db(game, output_db) != 0) {
        fprintf(stderr, "Error writing diagnostics database: %s\n", ec4x_get_last_error());
    }
    t_end = get_time_ms();
    printf("Database write completed in %.1fms\n\n", t_end - t_start);

    // Profiling summary
    double total_ms = total_ai_time + total_zero_turn_time + total_resolve_time + total_diagnostics_time;
    printf("================================================================================\n");
    printf("PERFORMANCE PROFILING SUMMARY (%d turns)\n", turn);
    printf("================================================================================\n");
    printf("AI Order Generation:   %8.1f ms (%5.1f%%)\n", total_ai_time, total_ai_time/total_ms*100);
    printf("  Zero-Turn Commands:  %8.1f ms (%5.1f%%)\n", total_zero_turn_time, total_zero_turn_time/total_ms*100);
    printf("Turn Resolution:       %8.1f ms (%5.1f%%)\n", total_resolve_time, total_resolve_time/total_ms*100);
    printf("Diagnostics:           %8.1f ms (%5.1f%%)\n", total_diagnostics_time, total_diagnostics_time/total_ms*100);
    printf("--------------------------------------------------------------------------------\n");
    printf("TOTAL:                 %8.1f ms (%6.2f seconds)\n", total_ms, total_ms/1000);
    printf("Average per turn:      %8.1f ms\n", total_ms/turn);
    printf("================================================================================\n\n");

    // Cleanup
    ec4x_destroy_game(game);
    return 0;
}

// =============================================================================
// Main Entry Point
// =============================================================================

void print_usage(const char* program_name) {
    printf("Usage: %s [OPTIONS]\n\n", program_name);
    printf("Options:\n");
    printf("  --players, -p N       Number of AI players (2-12, default: 4)\n");
    printf("  --turns, -t N         Maximum turns (default: 200)\n");
    printf("  --seed, -s N          Random seed (default: 42)\n");
    printf("  --rings, -r N         Map rings (1-5, default: 4)\n");
    printf("  --db FILE             SQLite database path (default: game_<seed>.db)\n");
    printf("  --help, -h            Show this help\n");
    printf("\n");
    printf("Examples:\n");
    printf("  %s --players 4 --turns 45 --seed 12345\n", program_name);
    printf("  %s -p 8 -t 100 -s 99999 --db custom.db\n", program_name);
}

int main(int argc, char** argv) {
    int num_players = 4;
    int max_turns = DEFAULT_TURNS;
    int64_t seed = DEFAULT_SEED;
    int map_rings = DEFAULT_RINGS;
    char* output_db = NULL;

    // Parse command-line arguments
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            print_usage(argv[0]);
            return 0;
        } else if (strcmp(argv[i], "--players") == 0 || strcmp(argv[i], "-p") == 0) {
            if (++i >= argc) { fprintf(stderr, "Missing value for %s\n", argv[i-1]); return 1; }
            num_players = atoi(argv[i]);
        } else if (strcmp(argv[i], "--turns") == 0 || strcmp(argv[i], "-t") == 0) {
            if (++i >= argc) { fprintf(stderr, "Missing value for %s\n", argv[i-1]); return 1; }
            max_turns = atoi(argv[i]);
        } else if (strcmp(argv[i], "--seed") == 0 || strcmp(argv[i], "-s") == 0) {
            if (++i >= argc) { fprintf(stderr, "Missing value for %s\n", argv[i-1]); return 1; }
            seed = atoll(argv[i]);
        } else if (strcmp(argv[i], "--rings") == 0 || strcmp(argv[i], "-r") == 0) {
            if (++i >= argc) { fprintf(stderr, "Missing value for %s\n", argv[i-1]); return 1; }
            map_rings = atoi(argv[i]);
        } else if (strcmp(argv[i], "--db") == 0) {
            if (++i >= argc) { fprintf(stderr, "Missing value for --db\n"); return 1; }
            output_db = argv[i];
        } else {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            print_usage(argv[0]);
            return 1;
        }
    }

    // Validate parameters
    if (num_players < 2 || num_players > MAX_PLAYERS) {
        fprintf(stderr, "Error: Number of players must be 2-12\n");
        return 1;
    }
    if (map_rings < 1 || map_rings > 5) {
        fprintf(stderr, "Error: Map rings must be 1-5\n");
        return 1;
    }

    // Default database path
    char default_db_path[256];
    if (output_db == NULL) {
        snprintf(default_db_path, sizeof(default_db_path),
                 "balance_results/diagnostics/game_%ld.db", seed);
        output_db = default_db_path;
    }

    // Initialize Nim runtime
    if (ec4x_init_runtime() != 0) {
        fprintf(stderr, "Error: Failed to initialize Nim runtime\n");
        return 1;
    }

    // Run simulation
    return run_simulation(num_players, max_turns, seed, map_rings, output_db);
}
