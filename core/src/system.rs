use crate::Hex;

#[derive(Debug, Clone)]
pub struct System {
    pub id: usize,
    pub coords: Hex,
    pub ring: u32,
    pub player: Option<usize>,
}

impl System {
    pub fn new(coords: Hex, ring: u32, num_rings: u32, player: Option<usize>) -> Self {
        let id = coords.to_id(num_rings);
        System {
            id,
            coords,
            ring,
            player,
        }
    }
}
