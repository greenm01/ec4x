#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Hex {
    pub q: i32,
    pub r: i32,
}

impl Hex {
    pub fn new(q: i32, r: i32) -> Self {
        Hex { q, r }
    }

    pub fn to_id(&self, num_rings: u32) -> usize {
        let max_coord = num_rings as i32 * 2;
        let q_shifted = self.q + num_rings as i32;
        let r_shifted = self.r + num_rings as i32;
        (q_shifted * (max_coord + 1) + r_shifted) as usize
    }

    pub fn distance(&self, other: &Hex) -> u32 {
        ((self.q - other.q).abs()
            + (self.r - other.r).abs()
            + (self.q + self.r - other.q - other.r).abs()) as u32
            / 2
    }

    pub fn within_radius(center: &Hex, radius: i32) -> Vec<Hex> {
        let mut results = Vec::new();
        for q in -radius..=radius {
            let r1 = (-radius).max(-q - radius);
            let r2 = radius.min(-q + radius);
            for r in r1..=r2 {
                results.push(Hex::new(center.q + q, center.r + r));
            }
        }
        results
    }

    pub fn neighbor(&self, direction: usize) -> Hex {
        let directions = [
            (1, 0),  // East
            (1, -1), // Northeast
            (0, -1), // Northwest
            (-1, 0), // West
            (-1, 1), // Southwest
            (0, 1),  // Southeast
        ];
        let (dq, dr) = directions[direction % 6];
        Hex::new(self.q + dq, self.r + dr)
    }
}
