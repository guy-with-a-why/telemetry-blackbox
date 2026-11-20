//! RUSTSEC-2026-0574: `FindMutView::pop` after a write through the view.
//!
//! A write through the view marks it as changed. On heapless 0.9.3, `pop` then
//! moves the value out, and the view's destructor still runs its re-sort: it
//! unlinks the same node a second time and pushes a second copy of the value
//! back into the list. With a `String`, both copies own one buffer, so once the
//! caller frees theirs the list holds a dangling pointer.
//!
//! `cargo miri test --locked` reports the use after free on 0.9.3. After
//! `cargo update -p heapless --precise 0.9.4` the same test passes.

#[cfg(test)]
mod tests {
    use heapless::sorted_linked_list::{Max, SortedLinkedList};

    #[test]
    fn pop_after_a_write_through_the_view() {
        let mut list: SortedLinkedList<String, Max, 3, u8> = SortedLinkedList::new_u8();
        for word in ["alpha", "bravo", "charlie"] {
            list.push(word.to_string()).unwrap();
        }

        // Max order puts charlie at the head, so bravo sits mid-list.
        let mut view = list.find_mut(|word| word == "bravo").unwrap();
        view.push('!');
        let popped = view.pop();
        assert_eq!(popped, "bravo!");
        drop(popped);

        // On 0.9.3 a second "bravo!" is back in the list, pointing at the
        // buffer just freed. Reading it is the use after free.
        let left: Vec<String> = core::iter::from_fn(|| list.pop()).collect();
        assert_eq!(left, ["charlie", "alpha"]);
    }
}
