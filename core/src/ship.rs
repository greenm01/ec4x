#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ShipType {
    Military,
    Spacelift,
}

#[derive(Debug, Clone)]
pub struct Ship {
    pub ship_type: ShipType,
    pub is_crippled: bool,
}

impl Ship {
    pub fn new(ship_type: ShipType, is_crippled: bool) -> Self {
        Ship {
            ship_type,
            is_crippled,
        }
    }

    pub fn can_cross_restricted_lane(&self) -> bool {
        match self.ship_type {
            ShipType::Military => !self.is_crippled,
            ShipType::Spacelift => false,
        }
    }
}
