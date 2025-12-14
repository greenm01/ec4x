/**
 * EC4X Sequential Simulation Orchestrator
 *
 * Simple C API test without pthread parallelization.
 * Proves the FFI works correctly before adding threading complexity.
 */

#include "ec4x_engine.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>

#define MAX_PLAYERS 12
#define DEFAULT_TURNS 200
#define DEFAULT_SEED 42
#define DEFAULT_RINGS 4

double get_time_ms() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0;
}

int run_simulation(int num_players, int max_turns, int64_t seed, int map_rings,
                   const char* output_db) {
    printf("=== EC4X Sequential Simulation ===\n");
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

    // Main simulation loop
    int turn = 1;
    int64_t turn_rng_seed = seed;

    for (turn = 1; turn <= max_turns; turn++) {
        if (turn % 10 == 0 || turn == 1) {
            printf("Turn %d/%d...\n", turn, max_turns);
        }

        EC4XOrders orders[MAX_PLAYERS];
        EC4XFilteredState filtered_states[MAX_PLAYERS];

        // SEQUENTIAL: Create filtered states
        t_start = get_time_ms();
        for (int i = 0; i < num_players; i++) {
            printf("  Creating filtered state for house %d...\n", i);
            filtered_states[i] = ec4x_create_filtered_state(game, i);
            if (filtered_states[i] == NULL) {
                fprintf(stderr, "Failed to create filtered state for house %d\n", i);
                ec4x_destroy_game(game);
                return 1;
            }
            printf("  Created filtered state for house %d\n", i);
        }

        // SEQUENTIAL: Generate AI orders
        for (int i = 0; i < num_players; i++) {
            printf("  Generating AI orders for house %d...\n", i);
            orders[i] = ec4x_generate_ai_orders(
                filtered_states[i],
                i,
                turn_rng_seed + i
            );
            printf("  Generated AI orders for house %d\n", i);
            if (orders[i] == NULL) {
                fprintf(stderr, "Error generating AI orders for house %d: %s\n",
                        i, ec4x_get_last_error());
                // Cleanup
                for (int j = 0; j < num_players; j++) {
                    ec4x_destroy_filtered_state(filtered_states[j]);
                }
                ec4x_destroy_game(game);
                return 1;
            }
        }
        t_end = get_time_ms();
        if (turn % 10 == 0 || turn == 1) {
            printf("  AI generation: %.1fms\n", t_end - t_start);
        }

        // Clean up filtered states (no longer needed)
        for (int i = 0; i < num_players; i++) {
            ec4x_destroy_filtered_state(filtered_states[i]);
        }

        // SEQUENTIAL: Execute zero-turn commands
        t_start = get_time_ms();
        for (int i = 0; i < num_players; i++) {
            if (ec4x_execute_zero_turn_commands(game, orders[i]) != 0) {
                fprintf(stderr, "Error executing zero-turn commands for house %d\n", i);
            }
        }

        // SEQUENTIAL: Resolve turn
        if (ec4x_resolve_turn(game, orders, num_players) != 0) {
            fprintf(stderr, "Error resolving turn %d: %s\n", turn, ec4x_get_last_error());
            for (int i = 0; i < num_players; i++) {
                ec4x_destroy_orders(orders[i]);
            }
            ec4x_destroy_game(game);
            return 1;
        }
        t_end = get_time_ms();
        if (turn % 10 == 0 || turn == 1) {
            printf("  Turn resolution: %.1fms\n", t_end - t_start);
        }

        // Clean up orders
        for (int i = 0; i < num_players; i++) {
            ec4x_destroy_orders(orders[i]);
        }

        // Collect diagnostics
        if (ec4x_collect_diagnostics(game, turn) != 0) {
            fprintf(stderr, "Warning: Failed to collect diagnostics for turn %d\n", turn);
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

    // Write diagnostics to database
    printf("Writing diagnostics to database...\n");
    t_start = get_time_ms();
    if (ec4x_write_diagnostics_db(game, output_db) != 0) {
        fprintf(stderr, "Error writing diagnostics database: %s\n", ec4x_get_last_error());
    }
    t_end = get_time_ms();
    printf("Database write completed in %.1fms\n", t_end - t_start);

    // Cleanup
    ec4x_destroy_game(game);

    printf("\nSimulation successful!\n");
    return 0;
}

void print_usage(const char* program_name) {
    printf("Usage: %s [OPTIONS]\n\n", program_name);
    printf("Options:\n");
    printf("  --players, -p N       Number of AI players (2-12, default: 4)\n");
    printf("  --turns, -t N         Maximum turns (default: 200)\n");
    printf("  --seed, -s N          Random seed (default: 42)\n");
    printf("  --rings, -r N         Map rings (1-5, default: 4)\n");
    printf("  --output-db FILE      SQLite database path (default: game_<seed>.db)\n");
    printf("  --help, -h            Show this help\n");
    printf("\n");
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
        } else if (strcmp(argv[i], "--output-db") == 0) {
            if (++i >= argc) { fprintf(stderr, "Missing value for --output-db\n"); return 1; }
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
        snprintf(default_db_path, sizeof(default_db_path), "game_%ld.db", seed);
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
