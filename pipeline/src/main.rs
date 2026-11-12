//! Decodes frames from Redpanda and loads them into ClickHouse with Spate.

fn main() {
    println!("{}", banner());
}

fn banner() -> &'static str {
    "pipeline: not built yet"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn banner_names_the_crate() {
        assert!(banner().starts_with("pipeline"));
    }
}
