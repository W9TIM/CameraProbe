// ESP-01S relay module case - parametric, two parts (base + friction-fit lid)
// Open in OpenSCAD, press F6 (render), then File > Export > STL.
// Set `part` to "base", "lid" or "both" (both = print layout, lid flipped).
//
// Orientation (matches Example Wiring.jpeg):
//   X = board length (37.3), Y = board width (25.3), Z = height.
//   FRONT wall (y = 0) is the terminal side: the cables leave through it.
//   The ESP-01S antenna end is the +X (right) end. Keep it plastic only.

part = "both";           // "base" | "lid" | "both"

// ---- Measured board (mm) ----
board_l = 37.3;
board_w = 25.3;
board_h = 16.8;          // tallest part (relay), measured from the PCB underside

// ---- Clearances (mm) ----
clr        = 1.0;        // gap on every side of the board (manufacturing variance)
len_extra  = 2.0;        // extra along the length for wire diameter
wire_depth = 4.0;        // extra room in front of the terminals for wires to bend out
top_clr    = 2.0;        // headroom above the tallest part (jumper wire, lid)

// ---- Structure (mm) ----
wall      = 2.0;
floor_t   = 2.0;
standoff  = 2.0;         // PCB underside to floor
lid_t     = 2.0;
lip_h     = 2.5;         // how far the lid lip goes into the base
lip_wall  = 1.2;
lip_tol   = 0.1;         // lid lip gap per side. NEGATIVE = oversize lip (interference).
                         // Tune this after measuring your print (see README note below).
bump_h    = 0.5;         // crush ribs on the lip: how far each rib sticks out past the lip face.
                         // The ribs do the gripping, so the lip itself can stay near nominal.
                         // Set 0 to turn the ribs off.
bump_w    = 2.0;         // rib width
corner_r  = 1.5;

// ---- Cable notches in the front wall (half-round, closed by the lid) ----
notch_d   = 6.5;         // fits a 2-conductor USB pigtail cable
notch_x   = [0.25, 0.65]; // positions as a fraction of inner length (input, output)

// ---- Mounting ears (set false for none) ----
ears      = true;
ear_hole  = 3.4;         // for #6 / M3 screws

// ---- Optional LED window on the lid (measure on the real board) ----
led_hole  = false;
led_x     = 0;           // mm from inner left edge
led_y     = 0;           // mm from inner front edge
led_d     = 3.0;

// ---- Derived ----
inner_l = board_l + 2*clr + len_extra;
inner_w = board_w + 2*clr + wire_depth;
inner_h = standoff + board_h + top_clr;
outer_l = inner_l + 2*wall;
outer_w = inner_w + 2*wall;
base_h  = floor_t + inner_h;

// Board origin inside the case (board sits against the back wall, wires get the front)
bx = wall + clr + len_extra/2;
by = wall + wire_depth + clr;

$fn = 40;

module rrect(l, w, h, r) {
    hull() for (x = [r, l - r], y = [r, w - r])
        translate([x, y, 0]) cylinder(r = r, h = h);
}

module base() {
    difference() {
        union() {
            rrect(outer_l, outer_w, base_h, corner_r);
            if (ears) for (sx = [0, 1])
                translate([sx == 0 ? -7 : outer_l - 3, outer_w/2 - 5, 0])
                    cube([10, 10, floor_t + 0.5]);
        }
        // cavity
        translate([wall, wall, floor_t]) cube([inner_l, inner_w, inner_h + 1]);
        // front wall cable notches (half-round at the top edge)
        for (f = notch_x)
            translate([wall + inner_l * f, -1, base_h])
                rotate([-90, 0, 0]) cylinder(d = notch_d, h = wall + 2);
        // ear screw holes
        if (ears) for (sx = [0, 1])
            translate([sx == 0 ? -2 : outer_l + 2, outer_w/2, -1])
                cylinder(d = ear_hole, h = floor_t + 3);
    }
    // PCB support pads at the four board corners
    for (x = [bx, bx + board_l - 3], y = [by, by + board_w - 3])
        translate([x, y, floor_t]) cube([3, 3, standoff]);
}

module lid() {
    difference() {
        union() {
            rrect(outer_l, outer_w, lid_t, corner_r);
            // lip that drops into the base opening
            // Lip outer face sits lip_tol short of the cavity wall on each side,
            // so it is a snug fit rather than loose.
            translate([wall + lip_tol, wall + lip_tol, lid_t])
                difference() {
                    cube([inner_l - 2*lip_tol, inner_w - 2*lip_tol, lip_h]);
                    translate([lip_wall, lip_wall, -0.01])
                        cube([inner_l - 2*lip_tol - 2*lip_wall,
                              inner_w - 2*lip_tol - 2*lip_wall, lip_h + 1]);
                }
            // Crush ribs: thin vertical ridges that press into the cavity walls.
            if (bump_h > 0) {
                lx = wall + lip_tol;  ly = wall + lip_tol;
                ll = inner_l - 2*lip_tol;  lw = inner_w - 2*lip_tol;
                // front and back faces (two ribs each)
                for (f = [0.3, 0.7]) {
                    translate([lx + ll*f - bump_w/2, ly - bump_h, lid_t]) cube([bump_w, bump_h + 0.2, lip_h]);
                    translate([lx + ll*f - bump_w/2, ly + lw - 0.2, lid_t]) cube([bump_w, bump_h + 0.2, lip_h]);
                }
                // left and right ends (one rib each)
                translate([lx - bump_h, ly + lw/2 - bump_w/2, lid_t]) cube([bump_h + 0.2, bump_w, lip_h]);
                translate([lx + ll - 0.2, ly + lw/2 - bump_w/2, lid_t]) cube([bump_h + 0.2, bump_w, lip_h]);
            }
        }
        // vent slots over the relay (left ~60% of the board)
        for (i = [0 : 3])
            translate([bx + 3 + i * 5, by + 6, -1]) cube([1.6, 14, lid_t + 2]);
        // optional LED window
        if (led_hole)
            translate([wall + led_x, wall + led_y, -1]) cylinder(d = led_d, h = lid_t + 2);
    }
}

if (part == "base") base();
else if (part == "lid") lid();
else {
    base();
    // lid flipped (lip up) beside the base for printing
    translate([outer_l + 12 + (ears ? 7 : 0), 0, 0]) lid();
}

echo(str("Outer size: ", outer_l, " x ", outer_w, " x ", base_h + lid_t, " mm (base+lid)"));
echo(str("Inner cavity: ", inner_l, " x ", inner_w, " x ", inner_h, " mm"));
