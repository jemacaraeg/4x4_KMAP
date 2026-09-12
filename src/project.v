`default_nettype none

module tt_um_vga_kmap (
    input wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input wire ena,
    input wire clk,
    input wire rst_n
);

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

    wire simplify_press = key_simplify ^ prev_simplify;
    wire up_press       = key_up       ^ prev_up;
    wire down_press     = key_down     ^ prev_down;
    wire left_press     = key_left     ^ prev_left;
    wire right_press    = key_right    ^ prev_right;
    wire toggle_press   = key_toggle   ^ prev_toggle;
    wire reset_press    = key_reset    ^ prev_reset;

    reg [1:0] cursor_row;
    reg [1:0] cursor_col;
    reg [15:0] kmap_value;
    reg simplify_mode;

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

    wire [3:0] selected_minterm =
        kmap_minterm(cursor_row, cursor_col);

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

    wire [9:0] tile_x =
        (tile_col == 2'd0) ? rel_x :
        (tile_col == 2'd1) ? rel_x - 10'd135 :
        (tile_col == 2'd2) ? rel_x - 10'd270 :
                             rel_x - 10'd405;

    wire [9:0] tile_y =
        (tile_row == 2'd0) ? rel_y :
        (tile_row == 2'd1) ? rel_y - 10'd75 :
        (tile_row == 2'd2) ? rel_y - 10'd150 :
                             rel_y - 10'd225;

    wire [3:0] display_minterm =
        kmap_minterm(tile_row, tile_col);

    wire display_value =
        kmap_value[display_minterm];

    wire selected_tile =
        (tile_row == cursor_row) &&
        (tile_col == cursor_col);

    wire digit_top =
        (tile_x >= 10'd53) &&
        (tile_x < 10'd82) &&
        (tile_y >= 10'd22) &&
        (tile_y < 10'd27);

    wire digit_bottom =
        (tile_x >= 10'd53) &&
        (tile_x < 10'd82) &&
        (tile_y >= 10'd48) &&
        (tile_y < 10'd53);

    wire digit_left =
        (tile_x >= 10'd49) &&
        (tile_x < 10'd54) &&
        (tile_y >= 10'd26) &&
        (tile_y < 10'd49);

    wire digit_right =
        (tile_x >= 10'd81) &&
        (tile_x < 10'd86) &&
        (tile_y >= 10'd26) &&
        (tile_y < 10'd49);

    wire digit_on =
        display_value ?
            digit_right :
            (digit_top |
             digit_bottom |
             digit_left |
             digit_right);

    function [15:0] cell_mask;
        input [1:0] r;
        input [1:0] c;
        reg [3:0] m;
        begin
            m = kmap_minterm(r, c);
            cell_mask = 16'b1 << m;
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

    /*
     * 4-CELL GROUPS
     *
     * Only the ordering of the 2x2 groups is changed.
     *
     * Original:
     * j=4 -> 3030 = 4,5,12,13
     * j=5 -> A0A0 = 5,7,13,15
     *
     * New:
     * j=4 -> A0A0
     * j=5 -> 3030
     *
     * Everything else remains in the same order.
     */

    function [15:0] group4;
        input [4:0] index;
        reg [4:0] j;
        reg [1:0] r;
        reg [1:0] c;

        begin
            if (index < 5'd4) begin

                r = index[1:0];

                group4 =
                    cell_mask(r, 2'd0) |
                    cell_mask(r, 2'd1) |
                    cell_mask(r, 2'd2) |
                    cell_mask(r, 2'd3);

            end

            else if (index < 5'd8) begin

                c = index[1:0];

                group4 =
                    cell_mask(2'd0, c) |
                    cell_mask(2'd1, c) |
                    cell_mask(2'd2, c) |
                    cell_mask(2'd3, c);

            end

            else begin

                j = index - 5'd8;

                /*
                 * Swap only j=4 and j=5.
                 */
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

                j = index;
                r = j[3:2];
                c = j[1:0];

                group2 =
                    cell_mask(r, c) |
                    cell_mask(r, c + 2'd1);

            end

            else begin

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
            group1 =
                cell_mask(index[3:2], index[1:0]);
        end
    endfunction

    reg [6:0] group_index [0:7];

    reg [6:0] solve_index;
    reg solving;

    reg [15:0] candidate_mask;
    reg [15:0] covered_minterms;
    reg [3:0] selected_group_count;

    integer sg;

    always @(*) begin
        candidate_mask = 16'b0;

        if (solve_index == 7'd0)
            candidate_mask = 16'hFFFF;

        else if (solve_index <= 7'd8)
            candidate_mask =
                group8(solve_index[2:0] - 3'd1);

        else if (solve_index <= 7'd32)
            candidate_mask =
                group4(solve_index - 7'd9);

        else if (solve_index <= 7'd64)
            candidate_mask =
                group2(solve_index - 7'd33);

        else
            candidate_mask =
                group1(solve_index - 7'd65);
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

                if ((kmap_value & candidate_mask) == candidate_mask) begin

                    if ((candidate_mask & ~covered_minterms) != 16'b0) begin

                        if (selected_group_count < 4'd8) begin

                            group_index[
                                selected_group_count[2:0]
                            ] <= solve_index;

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

                    solve_index <=
                        solve_index + 7'd1;

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

    /*
     * GROUP MEMBERSHIP
     *
     * Uses the SAME j swap as group4().
     *
     * Candidate numbers:
     *
     * 0       = 16-cell
     * 1..8    = 8-cell
     * 9..32   = 4-cell
     * 33..64  = 2-cell
     * 65..80  = 1-cell
     */

    function candidate_contains;
        input [6:0] index;
        input [3:0] minterm;

        reg [1:0] r;
        reg [1:0] c;
        reg [1:0] br;
        reg [1:0] bc;
        reg [4:0] j;

        begin

            r = {
                minterm[3],
                minterm[3] ^ minterm[2]
            };

            c = {
                minterm[1],
                minterm[1] ^ minterm[0]
            };

            candidate_contains = 1'b0;

            /*
             * 16-cell group
             */
            if (index == 7'd0) begin

                candidate_contains = 1'b1;

            end

            /*
             * 8-cell groups
             */
            else if (index <= 7'd4) begin

                br = index - 7'd1;

                if ((r == br) ||
                    (r == (br + 2'd1)))
                    candidate_contains = 1'b1;

            end

            else if (index <= 7'd8) begin

                bc = index - 7'd5;

                if ((c == bc) ||
                    (c == (bc + 2'd1)))
                    candidate_contains = 1'b1;

            end

            /*
             * 4-cell complete rows
             */
            else if (index <= 7'd12) begin

                br = index - 7'd9;

                if (r == br)
                    candidate_contains = 1'b1;

            end

            /*
             * 4-cell complete columns
             */
            else if (index <= 7'd16) begin

                bc = index - 7'd13;

                if (c == bc)
                    candidate_contains = 1'b1;

            end

            /*
             * 4-cell 2x2 groups
             *
             * Swap j=4 and j=5 so:
             *
             * A0A0 comes before 3030.
             */
            else if (index <= 7'd32) begin

                j = index - 7'd17;

                if (j == 5'd4)
                    j = 5'd5;
                else if (j == 5'd5)
                    j = 5'd4;

                br = j[3:2];
                bc = j[1:0];

                if (((r == br) ||
                     (r == (br + 2'd1))) &&
                    ((c == bc) ||
                     (c == (bc + 2'd1))))
                    candidate_contains = 1'b1;

            end

            /*
             * 2-cell horizontal groups
             */
            else if (index <= 7'd48) begin

                j = index - 7'd33;

                br = j[3:2];
                bc = j[1:0];

                if ((r == br) &&
                    ((c == bc) ||
                     (c == (bc + 2'd1))))
                    candidate_contains = 1'b1;

            end

            /*
             * 2-cell vertical groups
             */
            else if (index <= 7'd64) begin

                j = index - 7'd49;

                br = j[3:2];
                bc = j[1:0];

                if (((r == br) ||
                     (r == (br + 2'd1))) &&
                    (c == bc))
                    candidate_contains = 1'b1;

            end

            /*
             * 1-cell groups
             */
            else begin

                j = index - 7'd65;

                br = j[3:2];
                bc = j[1:0];

                if ((r == br) &&
                    (c == bc))
                    candidate_contains = 1'b1;

            end
        end
    endfunction

    wire edge_top =
        (tile_y < BORDER);

    wire edge_bottom =
        (tile_y >= TILE_H - BORDER);

    wire edge_left =
        (tile_x < BORDER);

    wire edge_right =
        (tile_x >= TILE_W - BORDER);

    wire edge_active =
        edge_top |
        edge_bottom |
        edge_left |
        edge_right;

    wire [1:0] border_neighbor_row =
        edge_top ?
            ((tile_row == 2'd0) ? 2'd3 : tile_row - 2'd1) :

        edge_bottom ?
            ((tile_row == 2'd3) ? 2'd0 : tile_row + 2'd1) :

            tile_row;

    wire [1:0] border_neighbor_col =
        edge_left ?
            ((tile_col == 2'd0) ? 2'd3 : tile_col - 2'd1) :

        edge_right ?
            ((tile_col == 2'd3) ? 2'd0 : tile_col + 2'd1) :

            tile_col;

    wire [3:0] border_neighbor_minterm =
        kmap_minterm(
            border_neighbor_row,
            border_neighbor_col
        );

    wire [7:0] border_current_groups = {
        candidate_contains(group_index[7], display_minterm),
        candidate_contains(group_index[6], display_minterm),
        candidate_contains(group_index[5], display_minterm),
        candidate_contains(group_index[4], display_minterm),
        candidate_contains(group_index[3], display_minterm),
        candidate_contains(group_index[2], display_minterm),
        candidate_contains(group_index[1], display_minterm),
        candidate_contains(group_index[0], display_minterm)
    };

    wire [7:0] border_neighbor_groups = {
        candidate_contains(group_index[7], border_neighbor_minterm),
        candidate_contains(group_index[6], border_neighbor_minterm),
        candidate_contains(group_index[5], border_neighbor_minterm),
        candidate_contains(group_index[4], border_neighbor_minterm),
        candidate_contains(group_index[3], border_neighbor_minterm),
        candidate_contains(group_index[2], border_neighbor_minterm),
        candidate_contains(group_index[1], border_neighbor_minterm),
        candidate_contains(group_index[0], border_neighbor_minterm)
    };

    wire [7:0] border_hits =
        border_current_groups &
        ~border_neighbor_groups;

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

    wire [2:0] border_rgb =
        border_color(border_hits);

    reg red;
    reg green;
    reg blue;

    always @(*) begin

        red   = 1'b0;
        green = 1'b0;
        blue  = 1'b0;

        if (display_on && inside_grid) begin

            if (simplify_mode) begin

                if (edge_active &&
                    (border_rgb != 3'b000)) begin

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

                if ((tile_x < BORDER) ||
                    (tile_x >= TILE_W - BORDER) ||
                    (tile_y < BORDER) ||
                    (tile_y >= TILE_H - BORDER)) begin

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

    assign uo_out[7] = hsync;
    assign uo_out[3] = vsync;

    assign uo_out[6] = red;
    assign uo_out[5] = green;
    assign uo_out[4] = blue;

    assign uo_out[2] = red;
    assign uo_out[1] = green;
    assign uo_out[0] = blue;

endmodule
