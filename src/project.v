`default_nettype none

module tt_um_vga_4x4_kmap (
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

    // Rising-edge detection
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
    // Reduced arithmetic and shared constants
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

    wire [9:0] tile_x = rel_x - (tile_col * 10'd135);
    wire [9:0] tile_y = rel_y - (tile_row * 10'd75);

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
    // K-MAP GROUP MASKS
    //
    // Candidate indices:
    //   0       = 16 cells
    //   1..8    = 8 cells
    //   9..32   = 4 cells
    //   33..64  = 2 cells
    //   65..80  = 1 cell
    //
    // The masks are arranged according to the K-map minterm
    // numbering, not ordinary binary row/column ordering.
    // ============================================================

    function [15:0] cell_mask;
        input [1:0] r;
        input [1:0] c;
        begin
            cell_mask = 16'b1 << kmap_minterm(r, c);
        end
    endfunction

    function [15:0] group8;
        input [2:0] index;
        begin
            case (index)
                3'd0: group8 = 16'h00FF;
                3'd1: group8 = 16'hF0F0;
                3'd2: group8 = 16'hFF00;
                3'd3: group8 = 16'h0F0F;
                3'd4: group8 = 16'h3333;
                3'd5: group8 = 16'hAAAA;
                3'd6: group8 = 16'hCCCC;
                default: group8 = 16'h5555;
            endcase
        end
    endfunction

    function [15:0] group4;
        input [4:0] index;
        reg [4:0] j;
        reg [1:0] r;
        reg [1:0] c;
        begin
            if (index < 5'd4) begin
                // Complete row
                r = index[1:0];

                group4 =
                    cell_mask(r, 2'd0) |
                    cell_mask(r, 2'd1) |
                    cell_mask(r, 2'd2) |
                    cell_mask(r, 2'd3);
            end
            else if (index < 5'd8) begin
                // Complete column
                c = index[1:0];

                group4 =
                    cell_mask(2'd0, c) |
                    cell_mask(2'd1, c) |
                    cell_mask(2'd2, c) |
                    cell_mask(2'd3, c);
            end
            else begin
                // 2x2 groups
                j = index - 5'd8;

                // Preserve your A0A0 / 3030 ordering
                if (j == 5'd4)
                    j = 5'd5;
                else if (j == 5'd5)
                    j = 5'd4;

                r = j[3:2];
                c = j[1:0];

                group4 =
                    cell_mask(r, c) |
                    cell_mask(r, c + 2'd1) |
                    cell_mask(r + 2'd1, c) |
                    cell_mask(r + 2'd1, c + 2'd1);
            end
        end
    endfunction

    function [15:0] group2;
        input [4:0] index;
        reg [4:0] j;
        reg [1:0] r;
        reg [1:0] c;
        begin
            if (index < 5'd16) begin
                // Horizontal groups
                j = index;
                r = j[3:2];
                c = j[1:0];

                group2 =
                    cell_mask(r, c) |
                    cell_mask(r, c + 2'd1);
            end
            else begin
                // Vertical groups
                j = index - 5'd16;
                r = j[3:2];
                c = j[1:0];

                group2 =
                    cell_mask(r, c) |
                    cell_mask(r + 2'd1, c);
            end
        end
    endfunction

    function [15:0] group1;
        input [3:0] index;
        begin
            group1 = cell_mask(index[3:2], index[1:0]);
        end
    endfunction

    // ============================================================
    // GROUP SOLVER
    //
    // Sequential search through candidate groups.
    // Only eight group indices are stored.
    // ============================================================

    reg [6:0] group_index [0:7];
    reg [6:0] solve_index;
    reg solving;

    reg [15:0] candidate_mask;
    reg [15:0] covered_minterms;
    reg [3:0] selected_group_count;

    integer sg;

    always @(*) begin
        case (solve_index)
            7'd0:
                candidate_mask = 16'hFFFF;

            7'd1, 7'd2, 7'd3, 7'd4,
            7'd5, 7'd6, 7'd7, 7'd8:
                candidate_mask = group8(solve_index - 7'd1);

            7'd9, 7'd10, 7'd11, 7'd12,
            7'd13, 7'd14, 7'd15, 7'd16,
            7'd17, 7'd18, 7'd19, 7'd20,
            7'd21, 7'd22, 7'd23, 7'd24,
            7'd25, 7'd26, 7'd27, 7'd28,
            7'd29, 7'd30, 7'd31, 7'd32:
                candidate_mask = group4(solve_index - 7'd9);

            7'd33, 7'd34, 7'd35, 7'd36,
            7'd37, 7'd38, 7'd39, 7'd40,
            7'd41, 7'd42, 7'd43, 7'd44,
            7'd45, 7'd46, 7'd47, 7'd48,
            7'd49, 7'd50, 7'd51, 7'd52,
            7'd53, 7'd54, 7'd55, 7'd56,
            7'd57, 7'd58, 7'd59, 7'd60,
            7'd61, 7'd62, 7'd63, 7'd64:
                candidate_mask = group2(solve_index - 7'd33);

            default:
                candidate_mask = group1(solve_index - 7'd65);
        endcase
    end

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
                group_index[sg] <= 7'd0;
        end
        else begin
            prev_simplify <= key_simplify;
            prev_up       <= key_up;
            prev_down     <= key_down;
            prev_left     <= key_left;
            prev_right    <= key_right;
            prev_toggle   <= key_toggle;
            prev_reset    <= key_reset;

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
                    group_index[sg] <= 7'd0;
            end
            else if (solving) begin

                // Select valid groups that cover at least one
                // previously uncovered 1.
                if ((kmap_value & candidate_mask) == candidate_mask) begin
                    if ((candidate_mask & ~covered_minterms) != 16'b0) begin
                        if (selected_group_count < 4'd8) begin
                            group_index[selected_group_count[2:0]]
                                <= solve_index;

                            selected_group_count <=
                                selected_group_count + 4'd1;

                            covered_minterms <=
                                covered_minterms | candidate_mask;
                        end
                    end
                end

                if (solve_index == 7'd80) begin
                    solving <= 1'b0;
                    simplify_mode <= 1'b1;
                end
                else begin
                    solve_index <= solve_index + 7'd1;
                end
            end
            else if (!simplify_mode) begin

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

                if (toggle_press)
                    kmap_value[selected_minterm] <=
                        ~kmap_value[selected_minterm];

                if (simplify_press) begin
                    selected_group_count <= 4'd0;
                    covered_minterms <= 16'b0;
                    solve_index <= 7'd0;
                    solving <= 1'b1;

                    for (sg = 0; sg < 8; sg = sg + 1)
                        group_index[sg] <= 7'd0;
                end
            end
        end
    end

    // ============================================================
    // GROUP MEMBERSHIP
    //
    // Used only for drawing group boundaries.
    // ============================================================

    function candidate_contains;
        input [6:0] index;
        input [3:0] minterm;

        reg [1:0] r;
        reg [1:0] c;
        reg [1:0] br;
        reg [1:0] bc;
        reg [4:0] j;

        begin
            // Convert minterm to Gray-code row and column
            r = {minterm[3], minterm[3] ^ minterm[2]};
            c = {minterm[1], minterm[1] ^ minterm[0]};

            candidate_contains = 1'b0;

            if (index == 7'd0) begin
                candidate_contains = 1'b1;
            end
            else if (index <= 7'd4) begin
                // 8-cell horizontal group
                br = index - 7'd1;

                if ((r == br) || (r == br + 2'd1))
                    candidate_contains = 1'b1;
            end
            else if (index <= 7'd8) begin
                // 8-cell vertical group
                bc = index - 7'd5;

                if ((c == bc) || (c == bc + 2'd1))
                    candidate_contains = 1'b1;
            end
            else if (index <= 7'd12) begin
                // Complete rows
                br = index - 7'd9;

                if (r == br)
                    candidate_contains = 1'b1;
            end
            else if (index <= 7'd16) begin
                // Complete columns
                bc = index - 7'd13;

                if (c == bc)
                    candidate_contains = 1'b1;
            end
            else if (index <= 7'd32) begin
                // 2x2 groups
                j = index - 7'd17;

                if (j == 5'd4)
                    j = 5'd5;
                else if (j == 5'd5)
                    j = 5'd4;

                br = j[3:2];
                bc = j[1:0];

                if (((r == br) || (r == br + 2'd1)) &&
                    ((c == bc) || (c == bc + 2'd1)))
                    candidate_contains = 1'b1;
            end
            else if (index <= 7'd48) begin
                // Horizontal 2-cell groups
                j = index - 7'd33;
                br = j[3:2];
                bc = j[1:0];

                if ((r == br) &&
                    ((c == bc) || (c == bc + 2'd1)))
                    candidate_contains = 1'b1;
            end
            else if (index <= 7'd64) begin
                // Vertical 2-cell groups
                j = index - 7'd49;
                br = j[3:2];
                bc = j[1:0];

                if (((r == br) || (r == br + 2'd1)) &&
                    (c == bc))
                    candidate_contains = 1'b1;
            end
            else begin
                // Single-cell groups
                j = index - 7'd65;
                br = j[3:2];
                bc = j[1:0];

                if ((r == br) && (c == bc))
                    candidate_contains = 1'b1;
            end
        end
    endfunction

    // ============================================================
    // GROUP BOUNDARIES
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
        candidate_contains(group_index[7], display_minterm),
        candidate_contains(group_index[6], display_minterm),
        candidate_contains(group_index[5], display_minterm),
        candidate_contains(group_index[4], display_minterm),
        candidate_contains(group_index[3], display_minterm),
        candidate_contains(group_index[2], display_minterm),
        candidate_contains(group_index[1], display_minterm),
        candidate_contains(group_index[0], display_minterm)
    };

    wire [7:0] neighbor_groups = {
        candidate_contains(group_index[7], neighbor_minterm),
        candidate_contains(group_index[6], neighbor_minterm),
        candidate_contains(group_index[5], neighbor_minterm),
        candidate_contains(group_index[4], neighbor_minterm),
        candidate_contains(group_index[3], neighbor_minterm),
        candidate_contains(group_index[2], neighbor_minterm),
        candidate_contains(group_index[1], neighbor_minterm),
        candidate_contains(group_index[0], neighbor_minterm)
    };

    wire [7:0] border_hits =
        current_groups & ~neighbor_groups;

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
                // Simplified mode: colored group boundaries
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
                // Normal mode: grid borders and 7-segment values
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
