use petgraph::graph::NodeIndex;
use petgraph::prelude::*;
use rand::seq::SliceRandom;
use rand::{thread_rng, Rng};
use std::cmp::{Ordering, Reverse};
use std::collections::{BinaryHeap, HashMap, HashSet};
use std::hash::{Hash, Hasher};

use crate::{Fleet, Hex, System};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum LaneType {
    Major,
    Minor,
    Restricted,
}

impl LaneType {
    pub fn weight(&self) -> u32 {
        match self {
            LaneType::Major => 1,
            LaneType::Minor => 2,
            LaneType::Restricted => 3,
        }
    }
}

#[derive(Debug, Clone)]
pub struct JumpLane {
    pub source: usize,
    pub destination: usize,
    pub lane_type: LaneType,
}

#[derive(Debug, Clone)]
pub struct StarMap {
    pub systems: HashMap<usize, System>,
    pub lanes: Vec<JumpLane>,
    pub graph: Graph<(), LaneType, Undirected>,
    system_id_to_node: HashMap<usize, NodeIndex>,
    player_count: usize,
    num_rings: u32,
    hub_id: usize,
}

impl StarMap {
    pub fn new(player_count: usize) -> Self {
        StarMap {
            systems: HashMap::new(),
            lanes: Vec::new(),
            graph: Graph::new_undirected(),
            system_id_to_node: HashMap::new(),
            player_count,
            num_rings: player_count as u32,
            hub_id: 0, // Will be updated when the hub is created
        }
    }

    pub fn add_system(&mut self, system: System) {
        let system_id = system.id;
        self.systems.insert(system_id, system);
        let node_index = self.graph.add_node(());
        self.system_id_to_node.insert(system_id, node_index);
    }

    pub fn populate(&mut self) {
        let center = Hex::new(0, 0);

        // Add hub system
        let hub = System::new(center, 0, self.num_rings, None);
        self.hub_id = hub.id;
        self.add_system(hub);

        // Generate all hexes within the radius
        let hexes = Hex::within_radius(&center, self.num_rings as i32);
        for hex in hexes {
            if hex == center {
                continue;
            }
            let ring = hex.distance(&center);
            let system = System::new(hex, ring, self.num_rings, None);
            self.add_system(system);
        }

        // Collect outer ring hexes sorted by angle
        let outer_ring_hexes = self
            .systems
            .values()
            .filter(|s| s.ring == self.num_rings)
            .map(|s| s.coords)
            .collect::<Vec<_>>();

        // Sort hexes by angle to distribute players evenly
        let mut sorted_outer_hexes = outer_ring_hexes.clone();
        sorted_outer_hexes.sort_by(|a, b| {
            let angle_a = (a.r as f64).atan2(a.q as f64);
            let angle_b = (b.r as f64).atan2(b.q as f64);
            angle_a.partial_cmp(&angle_b).unwrap()
        });

        let total_hexes = sorted_outer_hexes.len();
        let mut home_hexes = Vec::new();

        // Determine if we need to include hexes with four neighbors
        let use_vertices_only = self.player_count <= 6;

        // Try to assign vertices with 3 neighbors first
        let vertex_hexes = sorted_outer_hexes
            .iter()
            .filter(|hex| self.count_adjacent(hex) == 3)
            .cloned()
            .collect::<Vec<_>>();

        if use_vertices_only && vertex_hexes.len() < self.player_count {
            panic!("Not enough vertices with 3 neighbors for player home systems.");
        }

        // Use vertices as much as possible
        for i in 0..self.player_count {
            let fraction = i as f64 / self.player_count as f64;
            let index = (fraction * total_hexes as f64).round() as usize % total_hexes;
            let mut hex = sorted_outer_hexes[index];

            if use_vertices_only {
                // For six or fewer players, use vertices with exactly three neighbors
                hex = vertex_hexes[i % vertex_hexes.len()];
            } else {
                // For more than six players, include hexes with four neighbors
                let possible_hexes = sorted_outer_hexes.clone();
                hex = possible_hexes[index % possible_hexes.len()];
            }

            home_hexes.push(hex);
        }

        // Assign players to the selected home hexes
        for (i, hex) in home_hexes.iter().enumerate() {
            let system_id = hex.to_id(self.num_rings);
            let system = self.systems.get_mut(&system_id).expect("System not found");
            system.player = Some(i);
        }
    }

    fn count_adjacent(&self, hex: &Hex) -> usize {
        let directions = 0..6;
        directions
            .filter(|&dir| {
                let neighbor = hex.neighbor(dir);
                self.systems.values().any(|s| s.coords == neighbor)
            })
            .count()
    }

    pub fn generate_lanes(&mut self) {
        let mut rng = thread_rng();

        // Connect hub with exactly 6 Major lanes to first ring
        self.connect_hub();

        // Collect player system IDs
        let player_system_ids: Vec<usize> = self
            .systems
            .iter()
            .filter(|(_, system)| system.player.is_some())
            .map(|(&id, _)| id)
            .collect();

        // Connect player systems with exactly 3 major lanes to adjacent hexes
        for id in player_system_ids {
            self.connect_player_system(id);
        }

        // Collect outer ring system IDs (excluding player systems)
        let outer_system_ids: Vec<usize> = self
            .systems
            .iter()
            .filter(|(_, system)| system.ring == self.num_rings && system.player.is_none())
            .map(|(&id, _)| id)
            .collect();

        // Connect outer ring systems with random-type lanes to adjacent hexes
        for id in outer_system_ids {
            self.connect_outer_system(id, &mut rng);
        }

        // Collect inner system IDs (excluding hub and player systems)
        let inner_system_ids: Vec<usize> = self
            .systems
            .iter()
            .filter(|(_, system)| {
                system.ring > 0 && system.ring < self.num_rings && system.player.is_none()
            })
            .map(|(&id, _)| id)
            .collect();

        // Connect inner systems with random-type lanes to adjacent hexes
        for id in inner_system_ids {
            self.connect_inner_system(id, &mut rng);
        }
    }

    fn connect_hub(&mut self) {
        let hub_id = self.hub_id;
        let hub_coords = self
            .systems
            .get(&hub_id)
            .expect("Hub system not found")
            .coords;

        let neighbor_ids = self
            .systems
            .values()
            .filter(|s| s.ring == 1 && s.coords.distance(&hub_coords) == 1)
            .map(|s| s.id)
            .collect::<Vec<usize>>();

        if neighbor_ids.len() != 6 {
            panic!("Hub should have exactly 6 neighbors in the first ring");
        }

        for neighbor_id in neighbor_ids.iter() {
            self.add_lane(hub_id, *neighbor_id, LaneType::Major);
        }
    }

    fn connect_player_system(&mut self, id: usize) {
        let system = self.systems.get(&id).expect("Player system not found");
        let system_coords = system.coords;

        let mut neighbor_ids = (0..6)
            .filter_map(|dir| {
                let neighbor_coords = system_coords.neighbor(dir);
                self.systems
                    .values()
                    .find(|s| s.coords == neighbor_coords)
                    .map(|s| s.id)
            })
            .collect::<Vec<usize>>();

        neighbor_ids.sort();

        // Remove existing connections
        let existing_neighbors: HashSet<usize> = self
            .graph
            .neighbors(*self.system_id_to_node.get(&id).unwrap())
            .map(|n| self.get_system_id_by_node_index(n))
            .collect();

        neighbor_ids.retain(|n| !existing_neighbors.contains(n));

        // For home systems with more than three neighbors, connect to three of them
        neighbor_ids.shuffle(&mut thread_rng());
        let neighbors_to_connect = neighbor_ids.iter().take(3).cloned().collect::<Vec<_>>();

        if neighbors_to_connect.len() < 3 {
            panic!("Player system must have at least 3 neighbors");
        }

        for neighbor_id in neighbors_to_connect {
            self.add_lane(id, neighbor_id, LaneType::Major);
        }
    }

    fn connect_outer_system(&mut self, id: usize, rng: &mut impl Rng) {
        let system = self.systems.get(&id).expect("Outer system not found");
        let system_coords = system.coords;

        let neighbor_ids = (0..6)
            .filter_map(|dir| {
                let neighbor_coords = system_coords.neighbor(dir);
                self.systems
                    .values()
                    .find(|s| s.coords == neighbor_coords)
                    .map(|s| s.id)
            })
            .filter(|&nid| nid != id)
            .collect::<Vec<usize>>();

        // Remove existing connections
        let existing_neighbors: HashSet<usize> = self
            .graph
            .neighbors(*self.system_id_to_node.get(&id).unwrap())
            .map(|n| self.get_system_id_by_node_index(n))
            .collect();

        let available_neighbors: Vec<usize> = neighbor_ids
            .into_iter()
            .filter(|n| !existing_neighbors.contains(n))
            .collect();

        if available_neighbors.is_empty() {
            return;
        }

        for neighbor_id in available_neighbors.iter() {
            let lane_type = match rng.gen_range(0..3) {
                0 => LaneType::Major,
                1 => LaneType::Minor,
                _ => LaneType::Restricted,
            };
            self.add_lane(id, *neighbor_id, lane_type);
        }
    }

    fn connect_inner_system(&mut self, id: usize, rng: &mut impl Rng) {
        let system = self.systems.get(&id).expect("Inner system not found");
        let system_coords = system.coords;

        let neighbor_ids = (0..6)
            .filter_map(|dir| {
                let neighbor_coords = system_coords.neighbor(dir);
                self.systems
                    .values()
                    .find(|s| s.coords == neighbor_coords)
                    .map(|s| s.id)
            })
            .filter(|&nid| nid != id)
            .collect::<Vec<usize>>();

        // Remove existing connections
        let existing_neighbors: HashSet<usize> = self
            .graph
            .neighbors(*self.system_id_to_node.get(&id).unwrap())
            .map(|n| self.get_system_id_by_node_index(n))
            .collect();

        let available_neighbors: Vec<usize> = neighbor_ids
            .into_iter()
            .filter(|n| !existing_neighbors.contains(n))
            .collect();

        // Connect to all available neighbors
        for neighbor_id in available_neighbors {
            let lane_type = match rng.gen_range(0..3) {
                0 => LaneType::Major,
                1 => LaneType::Minor,
                _ => LaneType::Restricted,
            };
            self.add_lane(id, neighbor_id, lane_type);
        }
    }

    pub fn add_lane(&mut self, source: usize, destination: usize, lane_type: LaneType) {
        let source_node = *self
            .system_id_to_node
            .get(&source)
            .expect("Source node not found");
        let dest_node = *self
            .system_id_to_node
            .get(&destination)
            .expect("Destination node not found");

        if !self.graph.contains_edge(source_node, dest_node) {
            self.graph.add_edge(source_node, dest_node, lane_type);
            self.lanes.push(JumpLane {
                source,
                destination,
                lane_type,
            });
        }
    }

    pub fn get_system_id_by_node_index(&self, node_index: NodeIndex) -> usize {
        *self
            .system_id_to_node
            .iter()
            .find(|(_, &n)| n == node_index)
            .expect("NodeIndex not found in mapping")
            .0
    }

    pub fn astar(&self, start: &System, goal: &System, fleet: &Fleet) -> Option<Vec<System>> {
        let mut open_set = BinaryHeap::new();
        let mut came_from = HashMap::new();
        let mut g_score = HashMap::new();
        let mut f_score = HashMap::new();

        let start_id = start.id;
        let goal_id = goal.id;

        g_score.insert(start_id, 0);
        f_score.insert(
            start_id,
            self.systems[&start_id].coords.distance(&goal.coords),
        );

        open_set.push(Reverse((f_score[&start_id], start_id)));

        while let Some(Reverse((_, current))) = open_set.pop() {
            if current == goal_id {
                let mut total_path = vec![self.systems[&current].clone()];
                let mut current = current;
                while let Some(&prev) = came_from.get(&current) {
                    total_path.push(self.systems[&prev].clone());
                    current = prev;
                }
                total_path.reverse();
                return Some(total_path);
            }

            let current_node = *self.system_id_to_node.get(&current).unwrap();

            for edge in self.graph.edges(current_node) {
                let neighbor_node = edge.target();
                let neighbor = self.get_system_id_by_node_index(neighbor_node);
                let lane_type = edge.weight();

                if !fleet.can_traverse(*lane_type) {
                    continue;
                }

                let tentative_g_score = g_score[&current] + lane_type.weight();
                if tentative_g_score < *g_score.get(&neighbor).unwrap_or(&u32::MAX) {
                    came_from.insert(neighbor, current);
                    g_score.insert(neighbor, tentative_g_score);
                    f_score.insert(
                        neighbor,
                        tentative_g_score
                            + self.systems[&neighbor]
                                .coords
                                .distance(&self.systems[&goal_id].coords),
                    );
                    open_set.push(Reverse((f_score[&neighbor], neighbor)));
                }
            }
        }

        None
    }

    pub fn is_connected(&self) -> bool {
        let mut visited = HashSet::new();
        let mut stack = Vec::new();

        let start_node = *self.system_id_to_node.get(&self.hub_id).unwrap();

        visited.insert(start_node);
        stack.push(start_node);

        while let Some(current) = stack.pop() {
            for neighbor in self.graph.neighbors(current) {
                if visited.insert(neighbor) {
                    stack.push(neighbor);
                }
            }
        }

        visited.len() == self.systems.len()
    }
}
