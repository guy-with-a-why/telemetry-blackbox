//! Reads MAVLink frames from the serial link and publishes them to Redpanda.

fn main() {
    println!("{}", banner());
}

fn banner() -> &'static str {
    "gateway: not built yet"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn banner_names_the_crate() {
        assert!(banner().starts_with("gateway"));
    }
}
