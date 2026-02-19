module mux

pub enum SplitDir {
	horizontal // top/bottom split
	vertical   // left/right split
}

pub struct LayoutNode {
pub mut:
	is_leaf bool
	pane_id int
	dir     SplitDir
	ratio   f32 = f32(0.5)
	left    &LayoutNode = unsafe { nil }
	right   &LayoutNode = unsafe { nil }
	x       int
	y       int
	w       int
	h       int
}

pub fn new_layout(pane_id int, w int, h int) LayoutNode {
	return LayoutNode{
		is_leaf: true
		pane_id: pane_id
		x:       0
		y:       0
		w:       w
		h:       h
	}
}

// split finds the leaf holding active_id and splits it: active stays left/top,
// new_pane_id becomes right/bottom.
pub fn (mut n LayoutNode) split(active_id int, new_pane_id int, dir SplitDir) {
	if n.is_leaf {
		if n.pane_id == active_id {
			old_id   := n.pane_id
			n.is_leaf = false
			n.dir     = dir
			n.left    = &LayoutNode{is_leaf: true, pane_id: old_id}
			n.right   = &LayoutNode{is_leaf: true, pane_id: new_pane_id}
		}
		return
	}
	if !isnil(n.left)  { n.left.split(active_id, new_pane_id, dir) }
	if !isnil(n.right) { n.right.split(active_id, new_pane_id, dir) }
}

// remove removes the leaf with pane_id; its sibling absorbs the space.
pub fn (mut n LayoutNode) remove(pane_id int) {
	if n.is_leaf { return }

	left_match  := !isnil(n.left)  && n.left.is_leaf  && n.left.pane_id  == pane_id
	right_match := !isnil(n.right) && n.right.is_leaf && n.right.pane_id == pane_id

	if left_match && !isnil(n.right) {
		s        := n.right
		n.is_leaf = s.is_leaf
		n.pane_id = s.pane_id
		n.dir     = s.dir
		n.ratio   = s.ratio
		n.left    = s.left
		n.right   = s.right
		return
	}
	if right_match && !isnil(n.left) {
		s        := n.left
		n.is_leaf = s.is_leaf
		n.pane_id = s.pane_id
		n.dir     = s.dir
		n.ratio   = s.ratio
		n.left    = s.left
		n.right   = s.right
		return
	}
	if !isnil(n.left)  { n.left.remove(pane_id) }
	if !isnil(n.right) { n.right.remove(pane_id) }
}

// recalc recomputes all node geometries from the given bounding box.
pub fn (mut n LayoutNode) recalc(x int, y int, w int, h int) {
	n.x = x
	n.y = y
	n.w = w
	n.h = h
	if n.is_leaf { return }
	if n.dir == .vertical {
		left_w  := int(f32(w) * n.ratio)
		right_w := w - left_w - 1
		if !isnil(n.left)  { n.left.recalc(x, y, left_w, h) }
		if !isnil(n.right) { n.right.recalc(x + left_w + 1, y, right_w, h) }
	} else {
		top_h    := int(f32(h) * n.ratio)
		bottom_h := h - top_h - 1
		if !isnil(n.left)  { n.left.recalc(x, y, w, top_h) }
		if !isnil(n.right) { n.right.recalc(x, y + top_h + 1, w, bottom_h) }
	}
}

// adjust_ratio_dir adjusts the split ratio of the nearest ancestor node that
// matches dir and contains pane_id.  delta is signed (positive = grow left/top).
pub fn (mut n LayoutNode) adjust_ratio_dir(pane_id int, dir SplitDir, delta f32) {
	if n.is_leaf { return }
	ids := n.all_pane_ids()
	if pane_id in ids {
		if n.dir == dir {
			new_r := n.ratio + delta
			if new_r > f32(0.1) && new_r < f32(0.9) {
				n.ratio = new_r
			}
			return
		}
		if !isnil(n.left)  { n.left.adjust_ratio_dir(pane_id, dir, delta) }
		if !isnil(n.right) { n.right.adjust_ratio_dir(pane_id, dir, delta) }
	}
}

// find_neighbor returns the pane_id of the adjacent pane in the given direction,
// or -1 if none.
pub fn (n &LayoutNode) find_neighbor(pane_id int, dir SplitDir, toward_right bool) int {
	if n.is_leaf { return -1 }

	left_ids  := if !isnil(n.left)  { n.left.all_pane_ids()  } else { []int{} }
	right_ids := if !isnil(n.right) { n.right.all_pane_ids() } else { []int{} }

	if n.dir == dir {
		if pane_id in left_ids && toward_right {
			if !isnil(n.right) { return n.right.first_leaf() }
		}
		if pane_id in right_ids && !toward_right {
			if !isnil(n.left) { return n.left.last_leaf() }
		}
	}

	if pane_id in left_ids  && !isnil(n.left)  {
		r := n.left.find_neighbor(pane_id, dir, toward_right)
		if r >= 0 { return r }
	}
	if pane_id in right_ids && !isnil(n.right) {
		r := n.right.find_neighbor(pane_id, dir, toward_right)
		if r >= 0 { return r }
	}
	return -1
}

fn (n &LayoutNode) first_leaf() int {
	if n.is_leaf { return n.pane_id }
	if !isnil(n.left) { return n.left.first_leaf() }
	return -1
}

fn (n &LayoutNode) last_leaf() int {
	if n.is_leaf { return n.pane_id }
	if !isnil(n.right) { return n.right.last_leaf() }
	return -1
}

// all_pane_ids returns all leaf pane IDs under this node.
pub fn (n &LayoutNode) all_pane_ids() []int {
	if n.is_leaf { return [n.pane_id] }
	mut ids := []int{}
	if !isnil(n.left)  { ids << n.left.all_pane_ids() }
	if !isnil(n.right) { ids << n.right.all_pane_ids() }
	return ids
}

// get_geometry returns (x, y, w, h) for the leaf with pane_id, or (-1,-1,-1,-1).
pub fn (n &LayoutNode) get_geometry(pane_id int) (int, int, int, int) {
	if n.is_leaf {
		if n.pane_id == pane_id { return n.x, n.y, n.w, n.h }
		return -1, -1, -1, -1
	}
	if !isnil(n.left) {
		x, y, w, h := n.left.get_geometry(pane_id)
		if x >= 0 { return x, y, w, h }
	}
	if !isnil(n.right) {
		x, y, w, h := n.right.get_geometry(pane_id)
		if x >= 0 { return x, y, w, h }
	}
	return -1, -1, -1, -1
}
