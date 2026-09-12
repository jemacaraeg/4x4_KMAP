`default_nettype none

module tt_um_vga_kmap (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire ena,
    input  wire clk,
    input  wire rst_n
);

    // ============================================================
    // VGA
    // ============================================================

    wire hsync;
    wire vsync;
    wire display_on;
    wire [9:0] hpos;
    wire [9:0] vpos;

    hvsync_generator hvsync_gen (
        .clk(clk),
        .reset(!rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(display_on),
        .hpos(hpos),
        .vpos(vpos)
    );

    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;

    // ============================================================
    // INPUTS
    // ============================================================

    wire key_simplify = ui_in[0];
    wire key_up       = ui_in[1];
    wire key_down     = ui_in[2];
    wire key_left     = ui_in[3];
    wire key_right    = ui_in[4];
    wire key_toggle   = ui_in[5];
    wire key_reset    = ui_in[7];

    reg prev_simplify;
    reg prev_up;
    reg prev_down;
    reg prev_left;
    reg prev_right;
    reg prev_toggle;
    reg prev_reset;

    wire simplify_press = key_simplify & ~prev_simplify;
    wire up_press       = key_up       & ~prev_up;
    wire down_press     = key_down     & ~prev_down;
    wire left_press     = key_left     & ~prev_left;
    wire right_press    = key_right    & ~prev_right;
    wire toggle_press   = key_toggle   & ~prev_toggle;
    wire reset_press    = key_reset    & ~prev_reset;

    // ============================================================
    // K-MAP STATE
    // ============================================================

    reg [1:0] cursor_row;
    reg [1:0] cursor_col;
    reg [15:0] kmap_value;
    reg simplify_mode;

    // ============================================================
    // K-MAP ADDRESSING
    //
    // Gray-code ordering:
    // Rows: 00, 01, 11, 10
    // Cols: 00, 01, 11, 10
    // ============================================================

    function [3:0] kmap_minterm;
        input [1:0] r;
        input [1:0] c;
        begin
            kmap_minterm = {
                r[1],
                r[1] ^ r[0],
                c[1],
                c[1] ^ c[0]
            };
        end
    endfunction

    wire [3:0] selected_minterm;
    assign selected_minterm = kmap_minterm(cursor_row, cursor_col);

    // ============================================================
    // DISPLAY GEOMETRY
    // ============================================================

    localparam GRID_X = 90;
    localparam GRID_Y = 100;
    localparam TILE_W = 135;
    localparam TILE_H = 75;
    localparam GRID_W = 540;
    localparam GRID_H = 300;
    localparam BORDER = 4;

    wire inside_grid =
        (hpos >= GRID_X) &&
        (hpos < GRID_X + GRID_W) &&
        (vpos >= GRID_Y) &&
        (vpos < GRID_Y + GRID_H);

    wire [9:0] rel_x = hpos - GRID_X;
    wire [9:0] rel_y = vpos - GRID_Y;

    wire [1:0] tile_col =
        (rel_x < 10'd135) ? 2'd0 :
        (rel_x < 10'd270) ? 2'd1 :
        (rel_x < 10'd405) ? 2'd2 :
                            2'd3;

    wire [1:0] tile_row =
        (rel_y < 10'd75)  ? 2'd0 :
        (rel_y < 10'd150) ? 2'd1 :
        (rel_y < 10'd225) ? 2'd2 :
                            2'd3;

    // Multiplication by constants is replaced with shifts/additions.
    wire [9:0] col_offset =
        (tile_col == 2'd0) ? 10'd0 :
        (tile_col == 2'd1) ? 10'd135 :
        (tile_col == 2'd2) ? 10'd270 :
                            10'd405;

    wire [9:0] row_offset =
        (tile_row == 2'd0) ? 10'd0 :
        (tile_row == 2'd1) ? 10'd75 :
        (tile_row == 2'd2) ? 10'd150 :
                            10'd225;

    wire [9:0] tile_x = rel_x - col_offset;
    wire [9:0] tile_y = rel_y - row_offset;

    wire [3:0] display_minterm =
        kmap_minterm(tile_row, tile_col);

    wire display_value =
        kmap_value[display_minterm];

    wire selected_tile =
        (tile_row == cursor_row) &&
        (tile_col == cursor_col);

    // ============================================================
    // 7-SEGMENT DISPLAY
    // ============================================================

    wire digit_top =
        (tile_x >= 10'd53) && (tile_x < 10'd82) &&
        (tile_y >= 10'd22) && (tile_y < 10'd27);

    wire digit_bottom =
        (tile_x >= 10'd53) && (tile_x < 10'd82) &&
        (tile_y >= 10'd48) && (tile_y < 10'd53);

    wire digit_left =
        (tile_x >= 10'd49) && (tile_x < 10'd54) &&
        (tile_y >= 10'd26) && (tile_y < 10'd49);

    wire digit_right =
        (tile_x >= 10'd81) && (tile_x < 10'd86) &&
        (tile_y >= 10'd26) && (tile_y < 10'd49);

    wire digit_on =
        display_value ?
            digit_right :
            (digit_top | digit_bottom | digit_left | digit_right);

    // ============================================================
    // GROUP MASK GENERATOR
    //
    // Candidate numbering:
    //   0       = 16 cells
    //   1..8    = 8 cells
    //   9..32   = 4 cells
    //   33..64  = 2 cells
    //   65..80  = 1 cell
    //
    // This function generates the actual 16-bit mask.
    // The stored solver results are masks, not indices.
    // ============================================================

    function [15:0] cell_mask;
        input [1:0] r;
        input [1:0] c;
        begin
            cell_mask = 16'b1 << kmap_minterm(r, c);
        end
    endfunction

    function [15:0] make_candidate;
        input [6:0] index;

        reg [1:0] r;
        reg [1:0] c;
        reg [1:0] r2;
        reg [1:0] c2;
        reg [4:0] j;

        begin
            make_candidate = 16'b0;

            // ----------------------------------------------------
            // 16-cell group
            // ----------------------------------------------------
            if (index == 7'd0) begin
                make_candidate = 16'hFFFF;
            end

            // ----------------------------------------------------
            // 8-cell groups
            //
            // 1..4: pairs of rows
            // 5..8: pairs of columns
            // ----------------------------------------------------
            else if (index <= 7'd4) begin
                r = index - 7'd1;
                r2 = (r == 2'd3) ? 2'd0 : r + 2'd1;

                make_candidate =
                    cell_mask(r, 2'd0) |
                    cell_mask(r, 2'd1) |
                    cell_mask(r, 2'd2) |
                    cell_mask(r, 2'd3) |
                    cell_mask(r2, 2'd0) |
                    cell_mask(r2, 2'd1) |
                    cell_mask(r2, 2'd2) |
                    cell_mask(r2, 2'd3);
            end
            else if (index <= 7'd8) begin
                c = index - 7'd5;
                c2 = (c == 2'd3) ? 2'd0 : c + 2'd1;

                make_candidate =
                    cell_mask(2'd0, c) |
                    cell_mask(2'd1, c) |
                    cell_mask(2'd2, c) |
                    cell_mask(2'd3, c) |
                    cell_mask(2'd0, c2) |
                    cell_mask(2'd1, c2) |
                    cell_mask(2'd2, c2) |
                    cell_mask(2'd3, c2);
            end

            // ----------------------------------------------------
            // 4-cell groups
            //
            // 9..12: complete rows
            // 13..16: complete columns
            // 17..32: 2x2 groups
            // ----------------------------------------------------
            else if (index <= 7'd12) begin
                r = index - 7'd9;

                make_candidate =
                    cell_mask(r, 2'd0) |
                    cell_mask(r, 2'd1) |
                    cell_mask(r, 2'd2) |
                    cell_mask(r, 2'd3);
            end
            else if (index <= 7'd16) begin
                c = index - 7'd13;

                make_candidate =
                    cell_mask(2'd0, c) |
                    cell_mask(2'd1, c) |
                    cell_mask(2'd2, c) |
                    cell_mask(2'd3, c);
            end
            else if (index <= 7'd32) begin
                j = index - 7'd17;

                r = j[3:2];
                c = j[1:0];

                r2 = (r == 2'd3) ? 2'd0 : r + 2'd1;
                c2 = (c == 2'd3) ? 2'd0 : c + 2'd1;

                make_candidate =
                    cell_mask(r,  c)  |
                    cell_mask(r,  c2) |
                    cell_mask(r2, c)  |
                    cell_mask(r2, c2);
            end

            // ----------------------------------------------------
            // 2-cell groups
            //
            // 33..48: horizontal
            // 49..64: vertical
            // ----------------------------------------------------
            else if (index <= 7'd48) begin
                j = index - 7'd33;

                r = j[3:2];
                c = j[1:0];

                c2 = (c == 2'd3) ? 2'd0 : c + 2'd1;

                make_candidate =
                    cell_mask(r, c) |
                    cell_mask(r, c2);
            end
            else if (index <= 7'd64) begin
                j = index - 7'd49;

                r = j[3:2];
                c = j[1:0];

                r2 = (r == 2'd3) ? 2'd0 : r + 2'd1;

                make_candidate =
                    cell_mask(r, c) |
                    cell_mask(r2, c);
            end

            // ----------------------------------------------------
            // 1-cell groups
            //
            // 65..80
            // ----------------------------------------------------
            else begin
                j = index - 7'd65;

                r = j[3:2];
                c = j[1:0];

                make_candidate = cell_mask(r, c);
            end
        end
    endfunction

    // ============================================================
    // COMBINATIONAL CANDIDATE
    // ============================================================

    reg [15:0] candidate_mask;

    always @(*) begin
        candidate_mask = make_candidate(solve_index);
    end

    // ============================================================
    // GROUP SOLVER
    //
    // Greedy solver:
    // - scans candidates from largest to smallest
    // - accepts a group if all its cells are 1
    // - accepts it only if it covers a previously uncovered 1
    // - stores masks directly
    //
    // Eight group masks are stored.
    // ============================================================

    reg [15:0] group_mask [0:7];

    reg [6:0] solve_index;
    reg solving;

    reg [15:0] covered_minterms;
    reg [3:0] selected_group_count;

    integer sg;

    // ============================================================
    // SEQUENTIAL LOGIC
    // ============================================================

    always @(posedge clk) begin
        if (!rst_n) begin
            cursor_row <= 2'd0;
            cursor_col <= 2'd0;
            kmap_value <= 16'b0;
            simplify_mode <= 1'b0;

            prev_simplify <= 1'b0;
            prev_up       <= 1'b0;
            prev_down     <= 1'b0;
            prev_left     <= 1'b0;
            prev_right    <= 1'b0;
            prev_toggle   <= 1'b0;
            prev_reset    <= 1'b0;

            selected_group_count <= 4'd0;
            covered_minterms <= 16'b0;
            solve_index <= 7'd0;
            solving <= 1'b0;

            for (sg = 0; sg < 8; sg = sg + 1)
                group_mask[sg] <= 16'b0;
        end
        else begin

            // ----------------------------------------------------
            // Save previous button states
            // ----------------------------------------------------

            prev_simplify <= key_simplify;
            prev_up       <= key_up;
            prev_down     <= key_down;
            prev_left     <= key_left;
            prev_right    <= key_right;
            prev_toggle   <= key_toggle;
            prev_reset    <= key_reset;

            // ----------------------------------------------------
            // Reset
            // ----------------------------------------------------

            if (reset_press) begin
                cursor_row <= 2'd0;
                cursor_col <= 2'd0;
                kmap_value <= 16'b0;
                simplify_mode <= 1'b0;

                selected_group_count <= 4'd0;
                covered_minterms <= 16'b0;
                solve_index <= 7'd0;
                solving <= 1'b0;

                for (sg = 0; sg < 8; sg = sg + 1)
                    group_mask[sg] <= 16'b0;
            end

            // ----------------------------------------------------
            // Solver active
            // ----------------------------------------------------

            else if (solving) begin

                // Accept only valid implicants:
                // every cell in candidate must be 1.
                //
                // Also require at least one uncovered cell.

                if ((kmap_value & candidate_mask) == candidate_mask) begin
                    if ((candidate_mask & ~covered_minterms) != 16'b0) begin
                        if (selected_group_count < 4'd8) begin

                            group_mask[selected_group_count[2:0]]
                                <= candidate_mask;

                            selected_group_count <=
                                selected_group_count + 4'd1;

                            covered_minterms <=
                                covered_minterms | candidate_mask;
                        end
                    end
                end

                // Candidate 80 is the last candidate.
                if (solve_index == 7'd80) begin
                    solving <= 1'b0;
                    simplify_mode <= 1'b1;
                end
                else begin
                    solve_index <= solve_index + 7'd1;
                end
            end

            // ----------------------------------------------------
            // Normal interaction mode
            // ----------------------------------------------------

            else if (!simplify_mode) begin

                // Cursor movement

                if (up_press) begin
                    if (cursor_row == 2'd0)
                        cursor_row <= 2'd3;
                    else
                        cursor_row <= cursor_row - 2'd1;
                end

                if (down_press) begin
                    if (cursor_row == 2'd3)
                        cursor_row <= 2'd0;
                    else
                        cursor_row <= cursor_row + 2'd1;
                end

                if (left_press) begin
                    if (cursor_col == 2'd0)
                        cursor_col <= 2'd3;
                    else
                        cursor_col <= cursor_col - 2'd1;
                end

                if (right_press) begin
                    if (cursor_col == 2'd3)
                        cursor_col <= 2'd0;
                    else
                        cursor_col <= cursor_col + 2'd1;
                end

                // Toggle selected cell

                if (toggle_press)
                    kmap_value[selected_minterm] <=
                        ~kmap_value[selected_minterm];

                // Start simplification

                if (simplify_press) begin
                    selected_group_count <= 4'd0;
                    covered_minterms <= 16'b0;
                    solve_index <= 7'd0;
                    solving <= 1'b1;

                    for (sg = 0; sg < 8; sg = sg + 1)
                        group_mask[sg] <= 16'b0;
                end
            end
        end
    end

    // ============================================================
    // GROUP BOUNDARIES
    //
    // Direct mask lookup replaces candidate_contains().
    // This is substantially simpler than decoding group indices
    // for every VGA pixel.
    // ============================================================

    wire edge_top    = tile_y < BORDER;
    wire edge_bottom = tile_y >= TILE_H - BORDER;
    wire edge_left   = tile_x < BORDER;
    wire edge_right  = tile_x >= TILE_W - BORDER;

    wire edge_active =
        edge_top | edge_bottom | edge_left | edge_right;

    wire [1:0] neighbor_row =
        edge_top ?
            ((tile_row == 2'd0) ? 2'd3 : tile_row - 2'd1) :
        edge_bottom ?
            ((tile_row == 2'd3) ? 2'd0 : tile_row + 2'd1) :
            tile_row;

    wire [1:0] neighbor_col =
        edge_left ?
            ((tile_col == 2'd0) ? 2'd3 : tile_col - 2'd1) :
        edge_right ?
            ((tile_col == 2'd3) ? 2'd0 : tile_col + 2'd1) :
            tile_col;

    wire [3:0] neighbor_minterm =
        kmap_minterm(neighbor_row, neighbor_col);

    wire [7:0] current_groups = {
        group_mask[7][display_minterm],
        group_mask[6][display_minterm],
        group_mask[5][display_minterm],
        group_mask[4][display_minterm],
        group_mask[3][display_minterm],
        group_mask[2][display_minterm],
        group_mask[1][display_minterm],
        group_mask[0][display_minterm]
    };

    wire [7:0] neighbor_groups = {
        group_mask[7][neighbor_minterm],
        group_mask[6][neighbor_minterm],
        group_mask[5][neighbor_minterm],
        group_mask[4][neighbor_minterm],
        group_mask[3][neighbor_minterm],
        group_mask[2][neighbor_minterm],
        group_mask[1][neighbor_minterm],
        group_mask[0][neighbor_minterm]
    };

    wire [7:0] border_hits =
        current_groups & ~neighbor_groups;

    // ============================================================
    // BORDER COLOR
    // ============================================================

    function [2:0] border_color;
        input [7:0] hits;
        begin
            if (hits[0])
                border_color = 3'b001;
            else if (hits[1])
                border_color = 3'b010;
            else if (hits[2])
                border_color = 3'b011;
            else if (hits[3])
                border_color = 3'b100;
            else if (hits[4])
                border_color = 3'b101;
            else if (hits[5])
                border_color = 3'b110;
            else if (hits[6])
                border_color = 3'b001;
            else if (hits[7])
                border_color = 3'b010;
            else
                border_color = 3'b000;
        end
    endfunction

    wire [2:0] border_rgb = border_color(border_hits);

    // ============================================================
    // RGB OUTPUT
    // ============================================================

    reg red;
    reg green;
    reg blue;

    always @(*) begin
        red   = 1'b0;
        green = 1'b0;
        blue  = 1'b0;

        if (display_on && inside_grid) begin

            if (simplify_mode) begin

                // Simplified mode:
                // colored group boundaries only

                if (edge_active && (border_rgb != 3'b000)) begin
                    red   = border_rgb[2];
                    green = border_rgb[1];
                    blue  = border_rgb[0];
                end
                else if (digit_on) begin
                    red   = 1'b1;
                    green = 1'b1;
                    blue  = 1'b1;
                end
            end
            else begin

                // Normal mode:
                // grid borders and 7-segment values

                if (edge_active) begin
                    if (selected_tile) begin
                        red   = 1'b1;
                        green = 1'b1;
                        blue  = 1'b0;
                    end
                    else begin
                        red   = 1'b1;
                        green = 1'b1;
                        blue  = 1'b1;
                    end
                end
                else if (digit_on) begin
                    red   = 1'b1;
                    green = 1'b1;
                    blue  = 1'b1;
                end
            end
        end
    end

    // ============================================================
    // OUTPUT MAPPING
    // ============================================================

    assign uo_out[7] = hsync;
    assign uo_out[3] = vsync;

    assign uo_out[6] = red;
    assign uo_out[5] = green;
    assign uo_out[4] = blue;

    assign uo_out[2] = red;
    assign uo_out[1] = green;
    assign uo_out[0] = blue;

endmodule
