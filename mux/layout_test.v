module mux

// ---------------------------------------------------------------------------
// new_layout
// ---------------------------------------------------------------------------

fn test_new_layout_is_leaf() {
	n := new_layout(1, 80, 24)
	assert n.is_leaf == true
	assert n.pane_id == 1
}

fn test_new_layout_geometry() {
	n := new_layout(1, 80, 24)
	assert n.x == 0
	assert n.y == 0
	assert n.w == 80
	assert n.h == 24
}

fn test_new_layout_default_ratio() {
	n := new_layout(1, 80, 24)
	assert n.ratio == f32(0.5)
}

// ---------------------------------------------------------------------------
// all_pane_ids
// ---------------------------------------------------------------------------

fn test_all_pane_ids_single_pane() {
	n := new_layout(1, 80, 24)
	assert n.all_pane_ids() == [1]
}

fn test_all_pane_ids_after_vertical_split() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	ids := n.all_pane_ids()
	assert 1 in ids
	assert 2 in ids
	assert ids.len == 2
}

fn test_all_pane_ids_after_two_splits() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	n.split(2, 3, .horizontal)
	ids := n.all_pane_ids()
	assert ids.len == 3
	assert 1 in ids
	assert 2 in ids
	assert 3 in ids
}

// ---------------------------------------------------------------------------
// split
// ---------------------------------------------------------------------------

fn test_split_vertical_creates_internal_node() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	assert n.is_leaf == false
	assert n.dir     == .vertical
}

fn test_split_vertical_left_child_is_original_pane() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	assert !isnil(n.left)
	assert n.left.is_leaf  == true
	assert n.left.pane_id  == 1
}

fn test_split_vertical_right_child_is_new_pane() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	assert !isnil(n.right)
	assert n.right.is_leaf == true
	assert n.right.pane_id == 2
}

fn test_split_horizontal_dir() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .horizontal)
	assert n.dir == .horizontal
}

fn test_split_nested() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	n.split(2, 3, .horizontal) // split the right child
	ids := n.all_pane_ids()
	assert ids.len == 3
}

// ---------------------------------------------------------------------------
// recalc
// ---------------------------------------------------------------------------

fn test_recalc_single_pane_takes_full_area() {
	mut n := new_layout(1, 80, 24)
	n.recalc(0, 0, 80, 24)
	assert n.x == 0
	assert n.y == 0
	assert n.w == 80
	assert n.h == 24
}

fn test_recalc_vertical_split_left_width() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	n.recalc(0, 0, 80, 24)
	// left_w = int(80 * 0.5) = 40
	assert n.left.w  == 40
}

fn test_recalc_vertical_split_right_starts_after_divider() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	n.recalc(0, 0, 80, 24)
	// divider at col 40; right starts at col 41
	assert n.right.x == 41
	assert n.right.w == 39
}

fn test_recalc_horizontal_split_top_height() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .horizontal)
	n.recalc(0, 0, 80, 24)
	// top_h = int(24 * 0.5) = 12
	assert n.left.h  == 12
}

fn test_recalc_horizontal_split_bottom_starts_after_divider() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .horizontal)
	n.recalc(0, 0, 80, 24)
	// divider at row 12; bottom starts at row 13
	assert n.right.y == 13
	assert n.right.h == 11
}

fn test_recalc_children_have_correct_y_for_horizontal() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .horizontal)
	n.recalc(0, 0, 80, 24)
	assert n.left.y  == 0
	assert n.right.y == 13
}

fn test_recalc_children_inherit_full_width_for_horizontal() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .horizontal)
	n.recalc(0, 0, 80, 24)
	assert n.left.w  == 80
	assert n.right.w == 80
}

// ---------------------------------------------------------------------------
// get_geometry
// ---------------------------------------------------------------------------

fn test_get_geometry_single_pane() {
	mut n := new_layout(1, 80, 24)
	n.recalc(0, 0, 80, 24)
	x, y, w, h := n.get_geometry(1)
	assert x == 0
	assert y == 0
	assert w == 80
	assert h == 24
}

fn test_get_geometry_after_vertical_split() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	n.recalc(0, 0, 80, 24)
	x1, y1, w1, h1 := n.get_geometry(1)
	assert x1 == 0 && y1 == 0 && w1 == 40 && h1 == 24
	x2, y2, w2, h2 := n.get_geometry(2)
	assert x2 == 41 && y2 == 0 && w2 == 39 && h2 == 24
}

fn test_get_geometry_missing_pane_returns_minus_one() {
	n := new_layout(1, 80, 24)
	x, y, w, h := n.get_geometry(99)
	assert x == -1 && y == -1 && w == -1 && h == -1
}

// ---------------------------------------------------------------------------
// remove
// ---------------------------------------------------------------------------

fn test_remove_left_child_promotes_right() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	n.remove(1)
	// Tree should collapse to a single leaf for pane 2
	assert n.is_leaf  == true
	assert n.pane_id  == 2
}

fn test_remove_right_child_promotes_left() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	n.remove(2)
	assert n.is_leaf  == true
	assert n.pane_id  == 1
}

fn test_remove_leaves_single_pane_in_all_pane_ids() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	n.remove(1)
	assert n.all_pane_ids() == [2]
}

fn test_remove_from_nested_tree() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	n.split(2, 3, .horizontal)
	n.remove(3)
	ids := n.all_pane_ids()
	assert ids.len == 2
	assert 1 in ids
	assert 2 in ids
}

// ---------------------------------------------------------------------------
// find_neighbor
// ---------------------------------------------------------------------------

fn test_find_neighbor_right_in_vertical_split() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	// From pane 1 (left), navigate right → pane 2
	assert n.find_neighbor(1, .vertical, true) == 2
}

fn test_find_neighbor_left_in_vertical_split() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	// From pane 2 (right), navigate left → pane 1
	assert n.find_neighbor(2, .vertical, false) == 1
}

fn test_find_neighbor_down_in_horizontal_split() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .horizontal)
	// From pane 1 (top), navigate down → pane 2
	assert n.find_neighbor(1, .horizontal, true) == 2
}

fn test_find_neighbor_up_in_horizontal_split() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .horizontal)
	// From pane 2 (bottom), navigate up → pane 1
	assert n.find_neighbor(2, .horizontal, false) == 1
}

fn test_find_neighbor_wrong_direction_returns_minus_one() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical) // left/right split
	// Trying to navigate up/down across a vertical split → no neighbor
	assert n.find_neighbor(1, .horizontal, true) == -1
}

fn test_find_neighbor_single_pane_returns_minus_one() {
	n := new_layout(1, 80, 24)
	assert n.find_neighbor(1, .vertical,   true)  == -1
	assert n.find_neighbor(1, .horizontal, false) == -1
}

fn test_find_neighbor_rightmost_pane_has_no_right_neighbor() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	assert n.find_neighbor(2, .vertical, true) == -1
}

fn test_find_neighbor_leftmost_pane_has_no_left_neighbor() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	assert n.find_neighbor(1, .vertical, false) == -1
}

// ---------------------------------------------------------------------------
// adjust_ratio_dir
// ---------------------------------------------------------------------------

fn test_adjust_ratio_dir_vertical_increases_left() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	n.adjust_ratio_dir(1, .vertical, f32(0.1))
	assert n.ratio > f32(0.5)
}

fn test_adjust_ratio_dir_vertical_decreases_left() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	n.adjust_ratio_dir(1, .vertical, f32(-0.1))
	assert n.ratio < f32(0.5)
}

fn test_adjust_ratio_dir_clamps_to_min_ratio() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	// Push ratio below 0.1 — must clamp
	n.adjust_ratio_dir(1, .vertical, f32(-0.5))
	assert n.ratio == f32(0.5) // delta rejected because result < 0.1
}

fn test_adjust_ratio_dir_clamps_to_max_ratio() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	n.adjust_ratio_dir(1, .vertical, f32(0.5))
	assert n.ratio == f32(0.5) // delta rejected because result > 0.9
}

fn test_adjust_ratio_dir_wrong_direction_is_noop() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical) // vertical split
	before := n.ratio
	n.adjust_ratio_dir(1, .horizontal, f32(0.1)) // wrong dir
	assert n.ratio == before
}

fn test_adjust_ratio_dir_affects_recalc() {
	mut n := new_layout(1, 80, 24)
	n.split(1, 2, .vertical)
	n.recalc(0, 0, 80, 24)
	w_before := n.left.w
	n.adjust_ratio_dir(1, .vertical, f32(0.1))
	n.recalc(0, 0, 80, 24)
	assert n.left.w > w_before
}
