use ec4x_core::{Fleet, Ship, ShipType, StarMap};

#[test]
fn gen_starmap() {
    // generate a starmap and test fleets
    let player_count = 3;
    let mut star_map = StarMap::new(player_count);

    // Populate the star map with systems
    star_map.populate();

    // Generate lanes between systems
    star_map.generate_lanes();

    // Create a fleet
    let fleet = Fleet {
        ships: vec![
            Ship::new(ShipType::Military, false),
            Ship::new(ShipType::Spacelift, false),
        ],
    };

    // Find player home systems
    let start_system = star_map
        .systems
        .values()
        .find(|s| s.player == Some(0))
        .expect("Start system not found")
        .clone();
    let goal_system = star_map
        .systems
        .values()
        .find(|s| s.player == Some(1))
        .expect("Goal system not found")
        .clone();

    // Perform A* pathfinding
    if let Some(path) = star_map.astar(&start_system, &goal_system, &fleet) {
        println!("Path found for fleet from Player 0 to Player 1:");
        for system in &path {
            println!(
                "System {} at ({}, {}), Player: {:?}",
                system.id, system.coords.q, system.coords.r, system.player
            );
        }
    } else {
        println!("No path found for the fleet.");
    }

    // Verify connectivity
    if star_map.is_connected() {
        println!("StarMap is fully connected.");
    } else {
        println!("StarMap has unconnected systems.");
    }

    // Print all systems for verification
    println!("All Systems:");
    for system in star_map.systems.values() {
        let lanes = star_map
            .lanes
            .iter()
            .filter(|lane| lane.source == system.id || lane.destination == system.id)
            .map(|lane| {
                let other_id = if lane.source == system.id {
                    lane.destination
                } else {
                    lane.source
                };
                format!("{:?} to {}", lane.lane_type, other_id)
            })
            .collect::<Vec<String>>();
        println!(
            "ID: {}, Coords: ({}, {}), Ring: {}, Player: {:?}, Lanes: {:?}",
            system.id, system.coords.q, system.coords.r, system.ring, system.player, lanes
        );
    }
}
