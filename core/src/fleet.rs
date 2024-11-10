use crate::{LaneType, Ship};

#[derive(Debug, Clone)]
pub struct Fleet {
    pub ships: Vec<Ship>,
}

impl Fleet {
    pub fn can_traverse(&self, lane_type: LaneType) -> bool {
        match lane_type {
            LaneType::Restricted => self
                .ships
                .iter()
                .all(|ship| ship.can_cross_restricted_lane()),
            _ => true,
        }
    }
}
