`default_nettype none

module tt_um_vga_example (
    input wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input wire ena,
    input wire clk,
    input wire rst_n
);

    /* =========================================================
       VGA
       ========================================================= */

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


    /* =========================================================
       INPUT CONTROLS

       1 = UP
       2 = DOWN
       3 = LEFT
       4 = RIGHT
       5 = TOGGLE
       0 = SIMPLIFY
       7 = RESET
       ========================================================= */

    wire key_up       = ui_in[1];
    wire key_down     = ui_in[2];
    wire key_left     = ui_in[3];
    wire key_right    = ui_in[4];
    wire key_toggle   = ui_in[5];
    wire key_simplify = ui_in[0];
    wire key_reset    = ui_in[7];


    /* =========================================================
       EDGE DETECTION
       ========================================================= */

    reg prev_up;
    reg prev_down;
    reg prev_left;
    reg prev_right;
    reg prev_toggle;
    reg prev_reset;
    reg prev_simplify;

    wire up_press =
        key_up ^ prev_up;

    wire down_press =
        key_down ^ prev_down;

    wire left_press =
        key_left ^ prev_left;

    wire right_press =
        key_right ^ prev_right;

    wire toggle_press =
        key_toggle ^ prev_toggle;

    wire reset_press =
        key_reset ^ prev_reset;

    wire simplify_press =
        key_simplify ^ prev_simplify;


    /* =========================================================
       K-MAP STATE
       ========================================================= */

    reg [1:0] cursor_row;
    reg [1:0] cursor_col;

    reg [15:0] kmap_value;

    reg simplify_mode;


    /* =========================================================
       K-MAP MINTERM FUNCTION
       ========================================================= */

    function [3:0] kmap_minterm;
        input [1:0] r;
        input [1:0] c;

        begin
            case ({r,c})

                4'b0000: kmap_minterm = 4'd0;
                4'b0001: kmap_minterm = 4'd1;
                4'b0010: kmap_minterm = 4'd3;
                4'b0011: kmap_minterm = 4'd2;

                4'b0100: kmap_minterm = 4'd4;
                4'b0101: kmap_minterm = 4'd5;
                4'b0110: kmap_minterm = 4'd7;
                4'b0111: kmap_minterm = 4'd6;

                4'b1000: kmap_minterm = 4'd12;
                4'b1001: kmap_minterm = 4'd13;
                4'b1010: kmap_minterm = 4'd15;
                4'b1011: kmap_minterm = 4'd14;

                4'b1100: kmap_minterm = 4'd8;
                4'b1101: kmap_minterm = 4'd9;
                4'b1110: kmap_minterm = 4'd11;
                4'b1111: kmap_minterm = 4'd10;

                default:
                    kmap_minterm = 4'd0;

            endcase
        end
    endfunction


    wire [3:0] selected_minterm;

    assign selected_minterm =
        kmap_minterm(cursor_row,cursor_col);


    /* =========================================================
       MAIN STATE MACHINE
       ========================================================= */

    always @(posedge clk) begin

        if (!rst_n) begin

            cursor_row <= 2'd0;
            cursor_col <= 2'd0;

            kmap_value <= 16'b0;

            simplify_mode <= 1'b0;

            prev_up       <= 1'b0;
            prev_down     <= 1'b0;
            prev_left     <= 1'b0;
            prev_right    <= 1'b0;
            prev_toggle   <= 1'b0;
            prev_reset    <= 1'b0;
            prev_simplify <= 1'b0;

        end
        else begin

            prev_up       <= key_up;
            prev_down     <= key_down;
            prev_left     <= key_left;
            prev_right    <= key_right;
            prev_toggle   <= key_toggle;
            prev_reset    <= key_reset;
            prev_simplify <= key_simplify;


            if (reset_press) begin

                cursor_row <= 2'd0;
                cursor_col <= 2'd0;

                kmap_value <= 16'b0;

                simplify_mode <= 1'b0;

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

                if (toggle_press) begin

                    kmap_value[selected_minterm]
                        <= ~kmap_value[selected_minterm];

                end

                if (simplify_press) begin

                    simplify_mode <= 1'b1;

                end

            end

        end

    end


    /* =========================================================
       K-MAP GEOMETRY
       ========================================================= */

    localparam GRID_X = 90;
    localparam GRID_Y = 100;

    localparam TILE_W = 135;
    localparam TILE_H = 75;

    localparam GRID_W = 540;
    localparam GRID_H = 300;

    localparam BORDER = 4;


    wire inside_grid;

    assign inside_grid =
        (hpos >= GRID_X) &&
        (hpos < GRID_X + GRID_W) &&
        (vpos >= GRID_Y) &&
        (vpos < GRID_Y + GRID_H);


    wire [9:0] rel_x;
    wire [9:0] rel_y;

    assign rel_x = hpos - GRID_X;
    assign rel_y = vpos - GRID_Y;


    /* =========================================================
       TILE POSITION
       ========================================================= */

    reg [1:0] tile_col;
    reg [1:0] tile_row;

    always @(*) begin

        if (rel_x < 135)
            tile_col = 2'd0;
        else if (rel_x < 270)
            tile_col = 2'd1;
        else if (rel_x < 405)
            tile_col = 2'd2;
        else
            tile_col = 2'd3;


        if (rel_y < 75)
            tile_row = 2'd0;
        else if (rel_y < 150)
            tile_row = 2'd1;
        else if (rel_y < 225)
            tile_row = 2'd2;
        else
            tile_row = 2'd3;

    end


    wire [3:0] display_minterm;

    assign display_minterm =
        kmap_minterm(tile_row,tile_col);


    wire display_value;

    assign display_value =
        kmap_value[display_minterm];


    /* =========================================================
       SELECTED TILE
       ========================================================= */

    wire selected_tile;

    assign selected_tile =
        (tile_row == cursor_row) &&
        (tile_col == cursor_col);


    /* =========================================================
       POSITION INSIDE TILE
       ========================================================= */

    wire [9:0] tile_x;
    wire [9:0] tile_y;

    assign tile_x = rel_x % TILE_W;
    assign tile_y = rel_y % TILE_H;


    /* =========================================================
       MINTERM DISPLAY
       ========================================================= */

    wire digit_top;
    wire digit_bottom;
    wire digit_left;
    wire digit_right;

    assign digit_top =
        (tile_x >= 48) &&
        (tile_x < 87) &&
        (tile_y >= 17) &&
        (tile_y < 24);

    assign digit_bottom =
        (tile_x >= 48) &&
        (tile_x < 87) &&
        (tile_y >= 51) &&
        (tile_y < 58);

    assign digit_left =
        (tile_x >= 42) &&
        (tile_x < 49) &&
        (tile_y >= 23) &&
        (tile_y < 52);

    assign digit_right =
        (tile_x >= 86) &&
        (tile_x < 93) &&
        (tile_y >= 23) &&
        (tile_y < 52);


    wire digit_on;

    assign digit_on =
        display_value ?
            digit_right :
            (digit_top |
             digit_bottom |
             digit_left |
             digit_right);


    /* =========================================================
       GROUP CANDIDATE FUNCTIONS
       ========================================================= */

    function [15:0] group16;
        input integer index;

        begin
            group16 = 16'hFFFF;
        end
    endfunction


    function [15:0] group8;
        input integer index;

        begin

            case (index)

                0: group8 = 16'h00FF;
                1: group8 = 16'hF0F0;
                2: group8 = 16'hFF00;
                3: group8 = 16'h0F0F;

                4: group8 = 16'h3333;
                5: group8 = 16'hAAAA;
                6: group8 = 16'hCCCC;
                7: group8 = 16'h5555;

                default:
                    group8 = 16'h0000;

            endcase

        end
    endfunction


    function [15:0] group4;
        input integer index;

        begin

            case (index)

                0:  group4 = 16'h000F;
                1:  group4 = 16'h00F0;
                2:  group4 = 16'hF000;
                3:  group4 = 16'h0F00;

                4:  group4 = 16'h1111;
                5:  group4 = 16'h2222;
                6:  group4 = 16'h8888;
                7:  group4 = 16'h4444;

                8:  group4 = 16'h0033;
                9:  group4 = 16'h00AA;
                10: group4 = 16'h00CC;
                11: group4 = 16'h0055;

                12: group4 = 16'h3030;
                13: group4 = 16'hA0A0;
                14: group4 = 16'hC0C0;
                15: group4 = 16'h5050;

                16: group4 = 16'h3300;
                17: group4 = 16'hAA00;
                18: group4 = 16'hCC00;
                19: group4 = 16'h5500;

                20: group4 = 16'h0303;
                21: group4 = 16'h0A0A;
                22: group4 = 16'h0C0C;
                23: group4 = 16'h0505;

                default:
                    group4 = 16'h0000;

            endcase

        end
    endfunction


    function [15:0] group2;
        input integer index;

        begin

            case (index)

                0:  group2 = 16'h0003;
                1:  group2 = 16'h000A;
                2:  group2 = 16'h000C;
                3:  group2 = 16'h0005;

                4:  group2 = 16'h0030;
                5:  group2 = 16'h00A0;
                6:  group2 = 16'h00C0;
                7:  group2 = 16'h0050;

                8:  group2 = 16'h3000;
                9:  group2 = 16'hA000;
                10: group2 = 16'hC000;
                11: group2 = 16'h5000;

                12: group2 = 16'h0300;
                13: group2 = 16'h0A00;
                14: group2 = 16'h0C00;
                15: group2 = 16'h0500;

                16: group2 = 16'h0011;
                17: group2 = 16'h0022;
                18: group2 = 16'h0088;
                19: group2 = 16'h0044;

                20: group2 = 16'h1010;
                21: group2 = 16'h2020;
                22: group2 = 16'h8080;
                23: group2 = 16'h4040;

                24: group2 = 16'h1100;
                25: group2 = 16'h2200;
                26: group2 = 16'h8800;
                27: group2 = 16'h4400;

                28: group2 = 16'h0101;
                29: group2 = 16'h0202;
                30: group2 = 16'h0808;
                31: group2 = 16'h0404;

                default:
                    group2 = 16'h0000;

            endcase

        end
    endfunction


    function [15:0] group1;
        input integer index;

        begin

            case (index)

                0:  group1 = 16'h0001;
                1:  group1 = 16'h0002;
                2:  group1 = 16'h0008;
                3:  group1 = 16'h0004;

                4:  group1 = 16'h0010;
                5:  group1 = 16'h0020;
                6:  group1 = 16'h0080;
                7:  group1 = 16'h0040;

                8:  group1 = 16'h1000;
                9:  group1 = 16'h2000;
                10: group1 = 16'h8000;
                11: group1 = 16'h4000;

                12: group1 = 16'h0100;
                13: group1 = 16'h0200;
                14: group1 = 16'h0800;
                15: group1 = 16'h0400;

                default:
                    group1 = 16'h0000;

            endcase

        end
    endfunction


    /* =========================================================
       GROUP COLORS
       ========================================================= */

    function [2:0] group_color;
        input integer index;

        begin

            case (index % 6)

                0: group_color = 3'b001;
                1: group_color = 3'b010;
                2: group_color = 3'b011;
                3: group_color = 3'b100;
                4: group_color = 3'b101;
                5: group_color = 3'b110;

                default:
                    group_color = 3'b001;

            endcase

        end
    endfunction


    /* =========================================================
       SELECTED GROUP STORAGE
       ========================================================= */

    reg [15:0] selected_group_mask [0:15];
    reg [2:0]  selected_group_color [0:15];

    reg [4:0] selected_group_count;

    reg [15:0] covered_minterms;

    reg [15:0] candidate_mask;

    integer gi;
    integer gidx;


    always @(*) begin

        for (gi = 0; gi < 16; gi = gi + 1) begin

            selected_group_mask[gi]  = 16'b0;
            selected_group_color[gi] = 3'b000;

        end

        selected_group_count = 5'd0;
        covered_minterms = 16'b0;


        candidate_mask = group16(0);

        if ((kmap_value & candidate_mask) == candidate_mask) begin

            if ((candidate_mask & ~covered_minterms) != 16'b0) begin

                selected_group_mask[selected_group_count] =
                    candidate_mask;

                selected_group_color[selected_group_count] =
                    group_color(selected_group_count);

                selected_group_count =
                    selected_group_count + 1'b1;

                covered_minterms =
                    covered_minterms | candidate_mask;

            end

        end


        for (gidx = 0; gidx < 8; gidx = gidx + 1) begin

            candidate_mask = group8(gidx);

            if ((kmap_value & candidate_mask) == candidate_mask) begin

                if ((candidate_mask & ~covered_minterms) != 16'b0) begin

                    if (selected_group_count < 16) begin

                        selected_group_mask[selected_group_count] =
                            candidate_mask;

                        selected_group_color[selected_group_count] =
                            group_color(selected_group_count);

                        selected_group_count =
                            selected_group_count + 1'b1;

                        covered_minterms =
                            covered_minterms | candidate_mask;

                    end

                end

            end

        end


        for (gidx = 0; gidx < 24; gidx = gidx + 1) begin

            candidate_mask = group4(gidx);

            if ((kmap_value & candidate_mask) == candidate_mask) begin

                if ((candidate_mask & ~covered_minterms) != 16'b0) begin

                    if (selected_group_count < 16) begin

                        selected_group_mask[selected_group_count] =
                            candidate_mask;

                        selected_group_color[selected_group_count] =
                            group_color(selected_group_count);

                        selected_group_count =
                            selected_group_count + 1'b1;

                        covered_minterms =
                            covered_minterms | candidate_mask;

                    end

                end

            end

        end


        for (gidx = 0; gidx < 32; gidx = gidx + 1) begin

            candidate_mask = group2(gidx);

            if ((kmap_value & candidate_mask) == candidate_mask) begin

                if ((candidate_mask & ~covered_minterms) != 16'b0) begin

                    if (selected_group_count < 16) begin

                        selected_group_mask[selected_group_count] =
                            candidate_mask;

                        selected_group_color[selected_group_count] =
                            group_color(selected_group_count);

                        selected_group_count =
                            selected_group_count + 1'b1;

                        covered_minterms =
                            covered_minterms | candidate_mask;

                    end

                end

            end

        end


        for (gidx = 0; gidx < 16; gidx = gidx + 1) begin

            candidate_mask = group1(gidx);

            if ((kmap_value & candidate_mask) == candidate_mask) begin

                if ((candidate_mask & ~covered_minterms) != 16'b0) begin

                    if (selected_group_count < 16) begin

                        selected_group_mask[selected_group_count] =
                            candidate_mask;

                        selected_group_color[selected_group_count] =
                            group_color(selected_group_count);

                        selected_group_count =
                            selected_group_count + 1'b1;

                        covered_minterms =
                            covered_minterms | candidate_mask;

                    end

                end

            end

        end

    end


    /* =========================================================
       BOOLEAN EXPRESSION GENERATOR
       ========================================================= */

    reg [7:0] bool_text [0:127];
    reg [7:0] bool_text_len;

    integer bt_i;
    integer bt_g;
    integer bt_m;
    integer bt_pos;
    reg bt_a0, bt_a1;
    reg bt_b0, bt_b1;
    reg bt_c0, bt_c1;
    reg bt_d0, bt_d1;
    reg bt_first_term;

    always @(*) begin

        for (bt_i = 0; bt_i < 128; bt_i = bt_i + 1)
            bool_text[bt_i] = " ";

        bt_pos = 0;
        bt_first_term = 1'b1;

        if (simplify_mode) begin

            bool_text[0] = "F";
            bool_text[1] = " ";
            bool_text[2] = "=";
            bool_text[3] = " ";
            bt_pos = 4;

            if (kmap_value == 16'hFFFF) begin

                bool_text[bt_pos] = "1";
                bt_pos = bt_pos + 1;

            end
            else if (selected_group_count == 0) begin

                bool_text[bt_pos] = "0";
                bt_pos = bt_pos + 1;

            end
            else begin

                for (bt_g = 0; bt_g < 16; bt_g = bt_g + 1) begin

                    if (bt_g < selected_group_count) begin

                        if (!bt_first_term) begin
                            bool_text[bt_pos] = "+";
                            bt_pos = bt_pos + 1;
                        end

                        bt_first_term = 1'b0;

                        bt_a0=0;
                        bt_a1=0;
                        bt_b0=0;
                        bt_b1=0;
                        bt_c0=0;
                        bt_c1=0;
                        bt_d0=0;
                        bt_d1=0;

                        for (bt_m = 0; bt_m < 16; bt_m = bt_m + 1) begin

                            if (selected_group_mask[bt_g][bt_m]) begin

                                if (bt_m[3] == 0)
                                    bt_a0=1;
                                else
                                    bt_a1=1;

                                if (bt_m[2] == 0)
                                    bt_b0=1;
                                else
                                    bt_b1=1;

                                if (bt_m[1] == 0)
                                    bt_c0=1;
                                else
                                    bt_c1=1;

                                if (bt_m[0] == 0)
                                    bt_d0=1;
                                else
                                    bt_d1=1;

                            end

                        end


                        if (bt_a0 && !bt_a1) begin
                            bool_text[bt_pos]="A";
                            bt_pos=bt_pos+1;
                            bool_text[bt_pos]="'";
                            bt_pos=bt_pos+1;
                        end
                        else if (bt_a1 && !bt_a0) begin
                            bool_text[bt_pos]="A";
                            bt_pos=bt_pos+1;
                        end


                        if (bt_b0 && !bt_b1) begin
                            bool_text[bt_pos]="B";
                            bt_pos=bt_pos+1;
                            bool_text[bt_pos]="'";
                            bt_pos=bt_pos+1;
                        end
                        else if (bt_b1 && !bt_b0) begin
                            bool_text[bt_pos]="B";
                            bt_pos=bt_pos+1;
                        end


                        if (bt_c0 && !bt_c1) begin
                            bool_text[bt_pos]="C";
                            bt_pos=bt_pos+1;
                            bool_text[bt_pos]="'";
                            bt_pos=bt_pos+1;
                        end
                        else if (bt_c1 && !bt_c0) begin
                            bool_text[bt_pos]="C";
                            bt_pos=bt_pos+1;
                        end


                        if (bt_d0 && !bt_d1) begin
                            bool_text[bt_pos]="D";
                            bt_pos=bt_pos+1;
                            bool_text[bt_pos]="'";
                            bt_pos=bt_pos+1;
                        end
                        else if (bt_d1 && !bt_d0) begin
                            bool_text[bt_pos]="D";
                            bt_pos=bt_pos+1;
                        end

                    end

                end

            end

        end

        bool_text_len = bt_pos;


        for (bt_i = 0; bt_i < 64; bt_i = bt_i + 1) begin

            if ((bt_i + 53) < bt_pos)
                bool_text[64 + bt_i] = bool_text[bt_i + 53];
            else
                bool_text[64 + bt_i] = " ";

            if (bt_i >= 53)
                bool_text[bt_i] = " ";

        end

    end


    /* =========================================================
       GROUP BORDER DETECTION
       ========================================================= */

    wire [1:0] top_row =
        (tile_row == 2'd0) ? 2'd3 : tile_row - 2'd1;

    wire [1:0] bottom_row =
        (tile_row == 2'd3) ? 2'd0 : tile_row + 2'd1;

    wire [1:0] left_col =
        (tile_col == 2'd0) ? 2'd3 : tile_col - 2'd1;

    wire [1:0] right_col =
        (tile_col == 2'd3) ? 2'd0 : tile_col + 2'd1;


    wire [3:0] top_minterm =
        kmap_minterm(top_row,tile_col);

    wire [3:0] bottom_minterm =
        kmap_minterm(bottom_row,tile_col);

    wire [3:0] left_minterm =
        kmap_minterm(tile_row,left_col);

    wire [3:0] right_minterm =
        kmap_minterm(tile_row,right_col);


    /* =========================================================
       TWO-COLOR BORDER STORAGE

       Each side stores up to two distinct group colors.

       If two different groups share the same physical border,
       both colors are displayed as two adjacent bands.
       ========================================================= */

    reg [2:0] top_border_color1;
    reg [2:0] top_border_color2;

    reg [2:0] bottom_border_color1;
    reg [2:0] bottom_border_color2;

    reg [2:0] left_border_color1;
    reg [2:0] left_border_color2;

    reg [2:0] right_border_color1;
    reg [2:0] right_border_color2;

    reg [1:0] top_border_count;
    reg [1:0] bottom_border_count;
    reg [1:0] left_border_count;
    reg [1:0] right_border_count;

    integer bi;


    always @(*) begin

        top_border_color1    = 3'b000;
        top_border_color2    = 3'b000;

        bottom_border_color1 = 3'b000;
        bottom_border_color2 = 3'b000;

        left_border_color1   = 3'b000;
        left_border_color2   = 3'b000;

        right_border_color1  = 3'b000;
        right_border_color2  = 3'b000;

        top_border_count    = 2'd0;
        bottom_border_count = 2'd0;
        left_border_count   = 2'd0;
        right_border_count  = 2'd0;


        for (bi = 0; bi < 16; bi = bi + 1) begin

            if (bi < selected_group_count) begin


                /* TOP */

                if (selected_group_mask[bi][display_minterm] &&
                    !selected_group_mask[bi][top_minterm]) begin

                    if (top_border_count == 2'd0) begin

                        top_border_color1 =
                            selected_group_color[bi];

                        top_border_count =
                            2'd1;

                    end
                    else if ((top_border_count == 2'd1) &&
                             (selected_group_color[bi] !=
                              top_border_color1)) begin

                        top_border_color2 =
                            selected_group_color[bi];

                        top_border_count =
                            2'd2;

                    end

                end


                /* BOTTOM */

                if (selected_group_mask[bi][display_minterm] &&
                    !selected_group_mask[bi][bottom_minterm]) begin

                    if (bottom_border_count == 2'd0) begin

                        bottom_border_color1 =
                            selected_group_color[bi];

                        bottom_border_count =
                            2'd1;

                    end
                    else if ((bottom_border_count == 2'd1) &&
                             (selected_group_color[bi] !=
                              bottom_border_color1)) begin

                        bottom_border_color2 =
                            selected_group_color[bi];

                        bottom_border_count =
                            2'd2;

                    end

                end


                /* LEFT */

                if (selected_group_mask[bi][display_minterm] &&
                    !selected_group_mask[bi][left_minterm]) begin

                    if (left_border_count == 2'd0) begin

                        left_border_color1 =
                            selected_group_color[bi];

                        left_border_count =
                            2'd1;

                    end
                    else if ((left_border_count == 2'd1) &&
                             (selected_group_color[bi] !=
                              left_border_color1)) begin

                        left_border_color2 =
                            selected_group_color[bi];

                        left_border_count =
                            2'd2;

                    end

                end


                /* RIGHT */

                if (selected_group_mask[bi][display_minterm] &&
                    !selected_group_mask[bi][right_minterm]) begin

                    if (right_border_count == 2'd0) begin

                        right_border_color1 =
                            selected_group_color[bi];

                        right_border_count =
                            2'd1;

                    end
                    else if ((right_border_count == 2'd1) &&
                             (selected_group_color[bi] !=
                              right_border_color1)) begin

                        right_border_color2 =
                            selected_group_color[bi];

                        right_border_count =
                            2'd2;

                    end

                end

            end

        end

    end


    /* =========================================================
       TEXT SYSTEM
       ========================================================= */

    localparam TEXT_SCALE  = 2;
    localparam TEXT_CHAR_W = 12;
    localparam TEXT_CHAR_H = 14;

    localparam COL_TEXT_Y = 76;

    localparam COL1_X = 137;
    localparam COL2_X = 272;
    localparam COL3_X = 407;
    localparam COL4_X = 542;

    localparam ROW_TEXT_X = 30;

    localparam ROW1_Y = 125;
    localparam ROW2_Y = 200;
    localparam ROW3_Y = 275;
    localparam ROW4_Y = 350;

    localparam TITLE_Y = 40;

    localparam BOOL_Y1 = 416;
    localparam BOOL_Y2 = 430;

    localparam CONTROL_Y1 = 450;
    localparam CONTROL_Y2 = 466;

    localparam TITLE_CHARS = 28;
    localparam BOOL_MAX_CHARS = 64;

    localparam CONTROL1_X = 50;
    localparam CONTROL2_X = 194;
    localparam CONTROL1_CHARS = 45;
    localparam CONTROL2_CHARS = 31;


    /* =========================================================
       TEXT REGION DETECTION
       ========================================================= */

    wire inside_col1 =
        (hpos >= COL1_X) &&
        (hpos < COL1_X + 4 * TEXT_CHAR_W) &&
        (vpos >= COL_TEXT_Y) &&
        (vpos < COL_TEXT_Y + TEXT_CHAR_H);

    wire inside_col2 =
        (hpos >= COL2_X) &&
        (hpos < COL2_X + 3 * TEXT_CHAR_W) &&
        (vpos >= COL_TEXT_Y) &&
        (vpos < COL_TEXT_Y + TEXT_CHAR_H);

    wire inside_col3 =
        (hpos >= COL3_X) &&
        (hpos < COL3_X + 2 * TEXT_CHAR_W) &&
        (vpos >= COL_TEXT_Y) &&
        (vpos < COL_TEXT_Y + TEXT_CHAR_H);

    wire inside_col4 =
        (hpos >= COL4_X) &&
        (hpos < COL4_X + 3 * TEXT_CHAR_W) &&
        (vpos >= COL_TEXT_Y) &&
        (vpos < COL_TEXT_Y + TEXT_CHAR_H);


    wire inside_row1 =
        (hpos >= ROW_TEXT_X) &&
        (hpos < ROW_TEXT_X + 4 * TEXT_CHAR_W) &&
        (vpos >= ROW1_Y) &&
        (vpos < ROW1_Y + TEXT_CHAR_H);

    wire inside_row2 =
        (hpos >= ROW_TEXT_X) &&
        (hpos < ROW_TEXT_X + 3 * TEXT_CHAR_W) &&
        (vpos >= ROW2_Y) &&
        (vpos < ROW2_Y + TEXT_CHAR_H);

    wire inside_row3 =
        (hpos >= ROW_TEXT_X) &&
        (hpos < ROW_TEXT_X + 2 * TEXT_CHAR_W) &&
        (vpos >= ROW3_Y) &&
        (vpos < ROW3_Y + TEXT_CHAR_H);

    wire inside_row4 =
        (hpos >= ROW_TEXT_X) &&
        (hpos < ROW_TEXT_X + 3 * TEXT_CHAR_W) &&
        (vpos >= ROW4_Y) &&
        (vpos < ROW4_Y + TEXT_CHAR_H);


    wire inside_title =
        (hpos >= 158) &&
        (hpos < 158 + TITLE_CHARS * TEXT_CHAR_W) &&
        (vpos >= TITLE_Y) &&
        (vpos < TITLE_Y + TEXT_CHAR_H);


    wire [7:0] bool_second_len;

    assign bool_second_len =
        (bool_text_len > 8'd53) ?
        (bool_text_len - 8'd53) :
        8'd0;


    wire [9:0] bool_start_x;

    assign bool_start_x =
        (bool_text_len <= 8'd53) ?
        (10'd320 - ((bool_text_len * TEXT_CHAR_W) / 2)) :
        10'd2;


    wire [9:0] bool_second_x;

    assign bool_second_x =
        (bool_second_len != 0) ?
        (10'd320 - ((bool_second_len * TEXT_CHAR_W) / 2)) :
        10'd320;


    wire inside_bool1 =
        (hpos >= bool_start_x) &&
        (hpos < bool_start_x + BOOL_MAX_CHARS * TEXT_CHAR_W) &&
        (vpos >= BOOL_Y1) &&
        (vpos < BOOL_Y1 + TEXT_CHAR_H);

    wire inside_bool2 =
        (bool_second_len != 0) &&
        (hpos >= bool_second_x) &&
        (hpos < bool_second_x + BOOL_MAX_CHARS * TEXT_CHAR_W) &&
        (vpos >= BOOL_Y2) &&
        (vpos < BOOL_Y2 + TEXT_CHAR_H);


    wire inside_control1 =
        (hpos >= CONTROL1_X) &&
        (hpos < CONTROL1_X + CONTROL1_CHARS * TEXT_CHAR_W) &&
        (vpos >= CONTROL_Y1) &&
        (vpos < CONTROL_Y1 + TEXT_CHAR_H);

    wire inside_control2 =
        (hpos >= CONTROL2_X) &&
        (hpos < CONTROL2_X + CONTROL2_CHARS * TEXT_CHAR_W) &&
        (vpos >= CONTROL_Y2) &&
        (vpos < CONTROL_Y2 + TEXT_CHAR_H);


    wire inside_any_text =
        inside_title |
        inside_col1 |
        inside_col2 |
        inside_col3 |
        inside_col4 |
        inside_row1 |
        inside_row2 |
        inside_row3 |
        inside_row4 |
        inside_bool1 |
        inside_bool2 |
        inside_control1 |
        inside_control2;


    /* =========================================================
       TEXT COORDINATES
       ========================================================= */

    reg [9:0] text_local_x;
    reg [9:0] text_local_y;

    always @(*) begin

        text_local_x = 10'd0;
        text_local_y = 10'd0;

        if (inside_title) begin

            text_local_x = hpos - 158;
            text_local_y = vpos - TITLE_Y;

        end
        else if (inside_col1) begin

            text_local_x = hpos - COL1_X;
            text_local_y = vpos - COL_TEXT_Y;

        end
        else if (inside_col2) begin

            text_local_x = hpos - COL2_X;
            text_local_y = vpos - COL_TEXT_Y;

        end
        else if (inside_col3) begin

            text_local_x = hpos - COL3_X;
            text_local_y = vpos - COL_TEXT_Y;

        end
        else if (inside_col4) begin

            text_local_x = hpos - COL4_X;
            text_local_y = vpos - COL_TEXT_Y;

        end
        else if (inside_row1) begin

            text_local_x = hpos - ROW_TEXT_X;
            text_local_y = vpos - ROW1_Y;

        end
        else if (inside_row2) begin

            text_local_x = hpos - ROW_TEXT_X;
            text_local_y = vpos - ROW2_Y;

        end
        else if (inside_row3) begin

            text_local_x = hpos - ROW_TEXT_X;
            text_local_y = vpos - ROW3_Y;

        end
        else if (inside_row4) begin

            text_local_x = hpos - ROW_TEXT_X;
            text_local_y = vpos - ROW4_Y;

        end
        else if (inside_bool1) begin

            text_local_x = hpos - bool_start_x;
            text_local_y = vpos - BOOL_Y1;

        end
        else if (inside_bool2) begin

            text_local_x = hpos - bool_second_x;
            text_local_y = vpos - BOOL_Y2;

        end
        else if (inside_control1) begin

            text_local_x = hpos - CONTROL1_X;
            text_local_y = vpos - CONTROL_Y1;

        end
        else if (inside_control2) begin

            text_local_x = hpos - CONTROL2_X;
            text_local_y = vpos - CONTROL_Y2;

        end

    end


    wire [5:0] char_pos =
        text_local_x / TEXT_CHAR_W;

    wire [3:0] font_y =
        (text_local_y % TEXT_CHAR_H) / TEXT_SCALE;


    /* =========================================================
       CHARACTER GENERATOR
       ========================================================= */

    reg [7:0] control_char;

    always @(*) begin

        control_char = " ";

        if (inside_title) begin

            case (char_pos)

                0: control_char="4";
                1: control_char="X";
                2: control_char="4";
                3: control_char=" ";
                4: control_char="K";
                5: control_char="M";
                6: control_char="A";
                7: control_char="P";
                8: control_char=" ";
                9: control_char="B";
                10: control_char="Y";
                11: control_char=" ";
                12: control_char="B";
                13: control_char="A";
                14: control_char="G";
                15: control_char="A";
                16: control_char=" ";
                17: control_char="&";
                18: control_char=" ";
                19: control_char="M";
                20: control_char="A";
                21: control_char="C";
                22: control_char="A";
                23: control_char="R";
                24: control_char="A";
                25: control_char="E";
                26: control_char="G";

                default:
                    control_char=" ";

            endcase

        end
        else if (inside_col1) begin

            case (char_pos)

                0: control_char="C";
                1: control_char="'";
                2: control_char="D";
                3: control_char="'";

                default:
                    control_char=" ";

            endcase

        end
        else if (inside_col2) begin

            case (char_pos)

                0: control_char="C";
                1: control_char="'";
                2: control_char="D";

                default:
                    control_char=" ";

            endcase

        end
        else if (inside_col3) begin

            case (char_pos)

                0: control_char="C";
                1: control_char="D";

                default:
                    control_char=" ";

            endcase

        end
        else if (inside_col4) begin

            case (char_pos)

                0: control_char="C";
                1: control_char="D";
                2: control_char="'";

                default:
                    control_char=" ";

            endcase

        end
        else if (inside_row1) begin

            case (char_pos)

                0: control_char="A";
                1: control_char="'";
                2: control_char="B";
                3: control_char="'";

                default:
                    control_char=" ";

            endcase

        end
        else if (inside_row2) begin

            case (char_pos)

                0: control_char="A";
                1: control_char="'";
                2: control_char="B";

                default:
                    control_char=" ";

            endcase

        end
        else if (inside_row3) begin

            case (char_pos)

                0: control_char="A";
                1: control_char="B";

                default:
                    control_char=" ";

            endcase

        end
        else if (inside_row4) begin

            case (char_pos)

                0: control_char="A";
                1: control_char="B";
                2: control_char="'";

                default:
                    control_char=" ";

            endcase

        end
        else if (inside_bool1) begin

            control_char =
                bool_text[char_pos];

        end
        else if (inside_bool2) begin

            control_char =
                bool_text[64 + char_pos];

        end
        else if (inside_control1) begin

            case (char_pos)

                0: control_char="[";
                1: control_char="1";
                2: control_char="]";
                3: control_char=" ";

                4: control_char="U";
                5: control_char="P";
                6: control_char=" ";

                7: control_char="[";
                8: control_char="2";
                9: control_char="]";
                10: control_char=" ";

                11: control_char="D";
                12: control_char="O";
                13: control_char="W";
                14: control_char="N";
                15: control_char=" ";

                16: control_char="[";
                17: control_char="3";
                18: control_char="]";
                19: control_char=" ";

                20: control_char="L";
                21: control_char="E";
                22: control_char="F";
                23: control_char="T";
                24: control_char=" ";

                25: control_char="[";
                26: control_char="4";
                27: control_char="]";
                28: control_char=" ";

                29: control_char="R";
                30: control_char="I";
                31: control_char="G";
                32: control_char="H";
                33: control_char="T";
                34: control_char=" ";

                35: control_char="[";
                36: control_char="5";
                37: control_char="]";
                38: control_char=" ";

                39: control_char="T";
                40: control_char="O";
                41: control_char="G";
                42: control_char="G";
                43: control_char="L";
                44: control_char="E";

                default:
                    control_char=" ";

            endcase

        end
        else if (inside_control2) begin

            case (char_pos)

                0: control_char="[";
                1: control_char="0";
                2: control_char="]";
                3: control_char=" ";

                4: control_char="S";
                5: control_char="I";
                6: control_char="M";
                7: control_char="P";
                8: control_char="L";
                9: control_char="I";
                10: control_char="F";
                11: control_char="Y";

                12: control_char=" ";

                13: control_char="[";
                14: control_char="7";
                15: control_char="]";

                16: control_char=" ";

                17: control_char="R";
                18: control_char="E";
                19: control_char="S";
                20: control_char="E";
                21: control_char="T";

                default:
                    control_char=" ";

            endcase

        end

    end


    /* =========================================================
       FONT
       ========================================================= */

    function [4:0] font_row;
        input [7:0] ch;
        input [3:0] y;

        begin

            font_row = 5'b00000;

            case (ch)

                "A": begin
                    case(y)
                        0: font_row=5'b01110;
                        1: font_row=5'b10001;
                        2: font_row=5'b10001;
                        3: font_row=5'b11111;
                        4: font_row=5'b10001;
                        5: font_row=5'b10001;
                        6: font_row=5'b10001;
                        default: font_row=5'b00000;
                    endcase
                end

                "B": begin
                    case(y)
                        0: font_row=5'b11110;
                        1: font_row=5'b10001;
                        2: font_row=5'b10001;
                        3: font_row=5'b11110;
                        4: font_row=5'b10001;
                        5: font_row=5'b10001;
                        6: font_row=5'b11110;
                        default: font_row=5'b00000;
                    endcase
                end

                "C": begin
                    case(y)
                        0: font_row=5'b01110;
                        1: font_row=5'b10001;
                        2: font_row=5'b10000;
                        3: font_row=5'b10000;
                        4: font_row=5'b10000;
                        5: font_row=5'b10001;
                        6: font_row=5'b01110;
                        default: font_row=5'b00000;
                    endcase
                end

                "D": begin
                    case(y)
                        0: font_row=5'b11110;
                        1: font_row=5'b10001;
                        2: font_row=5'b10001;
                        3: font_row=5'b10001;
                        4: font_row=5'b10001;
                        5: font_row=5'b10001;
                        6: font_row=5'b11110;
                        default: font_row=5'b00000;
                    endcase
                end

                "E": begin
                    case(y)
                        0: font_row=5'b11111;
                        1: font_row=5'b10000;
                        2: font_row=5'b10000;
                        3: font_row=5'b11110;
                        4: font_row=5'b10000;
                        5: font_row=5'b10000;
                        6: font_row=5'b11111;
                        default: font_row=5'b00000;
                    endcase
                end

                "F": begin
                    case(y)
                        0: font_row=5'b11111;
                        1: font_row=5'b10000;
                        2: font_row=5'b10000;
                        3: font_row=5'b11110;
                        4: font_row=5'b10000;
                        5: font_row=5'b10000;
                        6: font_row=5'b10000;
                        default: font_row=5'b00000;
                    endcase
                end

                "G": begin
                    case(y)
                        0: font_row=5'b01110;
                        1: font_row=5'b10001;
                        2: font_row=5'b10000;
                        3: font_row=5'b10111;
                        4: font_row=5'b10001;
                        5: font_row=5'b10001;
                        6: font_row=5'b01110;
                        default: font_row=5'b00000;
                    endcase
                end

                "H": begin
                    case(y)
                        0: font_row=5'b10001;
                        1: font_row=5'b10001;
                        2: font_row=5'b10001;
                        3: font_row=5'b11111;
                        4: font_row=5'b10001;
                        5: font_row=5'b10001;
                        6: font_row=5'b10001;
                        default: font_row=5'b00000;
                    endcase
                end

                "I": begin
                    case(y)
                        0: font_row=5'b11111;
                        1: font_row=5'b00100;
                        2: font_row=5'b00100;
                        3: font_row=5'b00100;
                        4: font_row=5'b00100;
                        5: font_row=5'b00100;
                        6: font_row=5'b11111;
                        default: font_row=5'b00000;
                    endcase
                end

                "L": begin
                    case(y)
                        0: font_row=5'b10000;
                        1: font_row=5'b10000;
                        2: font_row=5'b10000;
                        3: font_row=5'b10000;
                        4: font_row=5'b10000;
                        5: font_row=5'b10000;
                        6: font_row=5'b11111;
                        default: font_row=5'b00000;
                    endcase
                end

                "M": begin
                    case(y)
                        0: font_row=5'b10001;
                        1: font_row=5'b11011;
                        2: font_row=5'b10101;
                        3: font_row=5'b10101;
                        4: font_row=5'b10001;
                        5: font_row=5'b10001;
                        6: font_row=5'b10001;
                        default: font_row=5'b00000;
                    endcase
                end

                "N": begin
                    case(y)
                        0: font_row=5'b10001;
                        1: font_row=5'b11001;
                        2: font_row=5'b10101;
                        3: font_row=5'b10011;
                        4: font_row=5'b10001;
                        5: font_row=5'b10001;
                        6: font_row=5'b10001;
                        default: font_row=5'b00000;
                    endcase
                end

                "O": begin
                    case(y)
                        0: font_row=5'b01110;
                        1: font_row=5'b10001;
                        2: font_row=5'b10001;
                        3: font_row=5'b10001;
                        4: font_row=5'b10001;
                        5: font_row=5'b10001;
                        6: font_row=5'b01110;
                        default: font_row=5'b00000;
                    endcase
                end

                "P": begin
                    case(y)
                        0: font_row=5'b11110;
                        1: font_row=5'b10001;
                        2: font_row=5'b10001;
                        3: font_row=5'b11110;
                        4: font_row=5'b10000;
                        5: font_row=5'b10000;
                        6: font_row=5'b10000;
                        default: font_row=5'b00000;
                    endcase
                end

                "R": begin
                    case(y)
                        0: font_row=5'b11110;
                        1: font_row=5'b10001;
                        2: font_row=5'b10001;
                        3: font_row=5'b11110;
                        4: font_row=5'b10100;
                        5: font_row=5'b10010;
                        6: font_row=5'b10001;
                        default: font_row=5'b00000;
                    endcase
                end

                "S": begin
                    case(y)
                        0: font_row=5'b01111;
                        1: font_row=5'b10000;
                        2: font_row=5'b10000;
                        3: font_row=5'b01110;
                        4: font_row=5'b00001;
                        5: font_row=5'b00001;
                        6: font_row=5'b11110;
                        default: font_row=5'b00000;
                    endcase
                end

                "T": begin
                    case(y)
                        0: font_row=5'b11111;
                        1: font_row=5'b00100;
                        2: font_row=5'b00100;
                        3: font_row=5'b00100;
                        4: font_row=5'b00100;
                        5: font_row=5'b00100;
                        6: font_row=5'b00100;
                        default: font_row=5'b00000;
                    endcase
                end

                "U": begin
                    case(y)
                        0: font_row=5'b10001;
                        1: font_row=5'b10001;
                        2: font_row=5'b10001;
                        3: font_row=5'b10001;
                        4: font_row=5'b10001;
                        5: font_row=5'b10001;
                        6: font_row=5'b01110;
                        default: font_row=5'b00000;
                    endcase
                end

                "W": begin
                    case(y)
                        0: font_row=5'b10001;
                        1: font_row=5'b10001;
                        2: font_row=5'b10001;
                        3: font_row=5'b10101;
                        4: font_row=5'b10101;
                        5: font_row=5'b11011;
                        6: font_row=5'b10001;
                        default: font_row=5'b00000;
                    endcase
                end

                "Y": begin
                    case(y)
                        0: font_row=5'b10001;
                        1: font_row=5'b10001;
                        2: font_row=5'b01010;
                        3: font_row=5'b00100;
                        4: font_row=5'b00100;
                        5: font_row=5'b00100;
                        6: font_row=5'b00100;
                        default: font_row=5'b00000;
                    endcase
                end

                "0": begin
                    case(y)
                        0: font_row=5'b01110;
                        1: font_row=5'b10001;
                        2: font_row=5'b10011;
                        3: font_row=5'b10101;
                        4: font_row=5'b11001;
                        5: font_row=5'b10001;
                        6: font_row=5'b01110;
                        default: font_row=5'b00000;
                    endcase
                end

                "1": begin
                    case(y)
                        0: font_row=5'b00100;
                        1: font_row=5'b01100;
                        2: font_row=5'b00100;
                        3: font_row=5'b00100;
                        4: font_row=5'b00100;
                        5: font_row=5'b00100;
                        6: font_row=5'b01110;
                        default: font_row=5'b00000;
                    endcase
                end

                "2": begin
                    case(y)
                        0: font_row=5'b01110;
                        1: font_row=5'b10001;
                        2: font_row=5'b00001;
                        3: font_row=5'b00010;
                        4: font_row=5'b00100;
                        5: font_row=5'b01000;
                        6: font_row=5'b11111;
                        default: font_row=5'b00000;
                    endcase
                end

                "3": begin
                    case(y)
                        0: font_row=5'b01110;
                        1: font_row=5'b10001;
                        2: font_row=5'b00001;
                        3: font_row=5'b00110;
                        4: font_row=5'b00001;
                        5: font_row=5'b10001;
                        6: font_row=5'b01110;
                        default: font_row=5'b00000;
                    endcase
                end

                "4": begin
                    case(y)
                        0: font_row=5'b00010;
                        1: font_row=5'b00110;
                        2: font_row=5'b01010;
                        3: font_row=5'b10010;
                        4: font_row=5'b11111;
                        5: font_row=5'b00010;
                        6: font_row=5'b00010;
                        default: font_row=5'b00000;
                    endcase
                end

                "5": begin
                    case(y)
                        0: font_row=5'b11111;
                        1: font_row=5'b10000;
                        2: font_row=5'b11110;
                        3: font_row=5'b00001;
                        4: font_row=5'b00001;
                        5: font_row=5'b10001;
                        6: font_row=5'b01110;
                        default: font_row=5'b00000;
                    endcase
                end

                "6": begin
                    case(y)
                        0: font_row=5'b00110;
                        1: font_row=5'b01000;
                        2: font_row=5'b10000;
                        3: font_row=5'b11110;
                        4: font_row=5'b10001;
                        5: font_row=5'b10001;
                        6: font_row=5'b01110;
                        default: font_row=5'b00000;
                    endcase
                end

                "7": begin
                    case(y)
                        0: font_row=5'b11111;
                        1: font_row=5'b00001;
                        2: font_row=5'b00010;
                        3: font_row=5'b00100;
                        4: font_row=5'b01000;
                        5: font_row=5'b01000;
                        6: font_row=5'b01000;
                        default: font_row=5'b00000;
                    endcase
                end

                "K": begin
                    case(y)
                        0: font_row=5'b10001;
                        1: font_row=5'b10010;
                        2: font_row=5'b10100;
                        3: font_row=5'b11000;
                        4: font_row=5'b10100;
                        5: font_row=5'b10010;
                        6: font_row=5'b10001;
                        default: font_row=5'b00000;
                    endcase
                end

                "X": begin
                    case(y)
                        0: font_row=5'b10001;
                        1: font_row=5'b10001;
                        2: font_row=5'b01010;
                        3: font_row=5'b00100;
                        4: font_row=5'b01010;
                        5: font_row=5'b10001;
                        6: font_row=5'b10001;
                        default: font_row=5'b00000;
                    endcase
                end

                "&": begin
                    case(y)
                        0: font_row=5'b01100;
                        1: font_row=5'b10010;
                        2: font_row=5'b10100;
                        3: font_row=5'b01000;
                        4: font_row=5'b10101;
                        5: font_row=5'b10010;
                        6: font_row=5'b01101;
                        default: font_row=5'b00000;
                    endcase
                end

                "=": begin
                    case(y)
                        2: font_row=5'b11111;
                        4: font_row=5'b11111;
                        default: font_row=5'b00000;
                    endcase
                end

                "+": begin
                    case(y)
                        1: font_row=5'b00100;
                        2: font_row=5'b00100;
                        3: font_row=5'b11111;
                        4: font_row=5'b00100;
                        5: font_row=5'b00100;
                        default: font_row=5'b00000;
                    endcase
                end

                "[": begin
                    case(y)
                        0: font_row=5'b01110;
                        1: font_row=5'b01000;
                        2: font_row=5'b01000;
                        3: font_row=5'b01000;
                        4: font_row=5'b01000;
                        5: font_row=5'b01000;
                        6: font_row=5'b01110;
                        default: font_row=5'b00000;
                    endcase
                end

                "]": begin
                    case(y)
                        0: font_row=5'b01110;
                        1: font_row=5'b00010;
                        2: font_row=5'b00010;
                        3: font_row=5'b00010;
                        4: font_row=5'b00010;
                        5: font_row=5'b00010;
                        6: font_row=5'b01110;
                        default: font_row=5'b00000;
                    endcase
                end

                "'": begin
                    case(y)
                        0: font_row=5'b00100;
                        1: font_row=5'b00100;
                        default: font_row=5'b00000;
                    endcase
                end

                default:
                    font_row = 5'b00000;

            endcase

        end
    endfunction


    wire [4:0] font_bits;

    assign font_bits =
        font_row(control_char,font_y);


    wire font_pixel;

    assign font_pixel =
        ((text_local_x % TEXT_CHAR_W) < 10) ?
        font_bits[
            4 - ((text_local_x % TEXT_CHAR_W) / TEXT_SCALE)
        ] :
        1'b0;


    /* =========================================================
       VGA PIXEL OUTPUT
       ========================================================= */

    reg red;
    reg green;
    reg blue;

    always @(*) begin

        red   = 1'b0;
        green = 1'b0;
        blue  = 1'b0;


        if (display_on) begin

            if (inside_grid) begin

                if (simplify_mode) begin


                    /* =================================================
                       FULL 16-CELL GROUP

                       Only the outside border of the entire
                       4x4 K-map is drawn.
                       ================================================= */

                    if ((kmap_value == 16'hFFFF) &&
                        ((rel_x < BORDER) ||
                         (rel_x >= GRID_W - BORDER) ||
                         (rel_y < BORDER) ||
                         (rel_y >= GRID_H - BORDER))) begin

                        red   = 1'b1;
                        green = 1'b0;
                        blue  = 1'b1;

                    end


                    /* =================================================
                       TOP BORDER

                       One group:
                       entire 4-pixel border = color 1

                       Two groups:
                       first 2 pixels = color 1
                       second 2 pixels = color 2
                       ================================================= */

                    else if ((tile_y < BORDER) &&
                             (top_border_count != 2'd0)) begin

                        if (top_border_count == 2'd1) begin

                            red   = top_border_color1[2];
                            green = top_border_color1[1];
                            blue  = top_border_color1[0];

                        end
                        else if (tile_y < (BORDER / 2)) begin

                            red   = top_border_color1[2];
                            green = top_border_color1[1];
                            blue  = top_border_color1[0];

                        end
                        else begin

                            red   = top_border_color2[2];
                            green = top_border_color2[1];
                            blue  = top_border_color2[0];

                        end

                    end


                    /* =================================================
                       BOTTOM BORDER
                       ================================================= */

                    else if ((tile_y >= TILE_H - BORDER) &&
                             (bottom_border_count != 2'd0)) begin

                        if (bottom_border_count == 2'd1) begin

                            red   = bottom_border_color1[2];
                            green = bottom_border_color1[1];
                            blue  = bottom_border_color1[0];

                        end
                        else if (tile_y < TILE_H - (BORDER / 2)) begin

                            red   = bottom_border_color1[2];
                            green = bottom_border_color1[1];
                            blue  = bottom_border_color1[0];

                        end
                        else begin

                            red   = bottom_border_color2[2];
                            green = bottom_border_color2[1];
                            blue  = bottom_border_color2[0];

                        end

                    end


                    /* =================================================
                       LEFT BORDER
                       ================================================= */

                    else if ((tile_x < BORDER) &&
                             (left_border_count != 2'd0)) begin

                        if (left_border_count == 2'd1) begin

                            red   = left_border_color1[2];
                            green = left_border_color1[1];
                            blue  = left_border_color1[0];

                        end
                        else if (tile_x < (BORDER / 2)) begin

                            red   = left_border_color1[2];
                            green = left_border_color1[1];
                            blue  = left_border_color1[0];

                        end
                        else begin

                            red   = left_border_color2[2];
                            green = left_border_color2[1];
                            blue  = left_border_color2[0];

                        end

                    end


                    /* =================================================
                       RIGHT BORDER
                       ================================================= */

                    else if ((tile_x >= TILE_W - BORDER) &&
                             (right_border_count != 2'd0)) begin

                        if (right_border_count == 2'd1) begin

                            red   = right_border_color1[2];
                            green = right_border_color1[1];
                            blue  = right_border_color1[0];

                        end
                        else if (tile_x < TILE_W - (BORDER / 2)) begin

                            red   = right_border_color1[2];
                            green = right_border_color1[1];
                            blue  = right_border_color1[0];

                        end
                        else begin

                            red   = right_border_color2[2];
                            green = right_border_color2[1];
                            blue  = right_border_color2[0];

                        end

                    end


                    /* =================================================
                       MINTERM DISPLAY

                       Keep all 0s visible.
                       ================================================= */

                    else if (digit_on) begin

                        red   = 1'b1;
                        green = 1'b1;
                        blue  = 1'b1;

                    end

                end


                /* =================================================
                   NORMAL K-MAP / SELECTOR VIEW
                   ================================================= */

                else begin

                    if (selected_tile) begin

                        if ((tile_x < BORDER) ||
                            (tile_x >= TILE_W - BORDER) ||
                            (tile_y < BORDER) ||
                            (tile_y >= TILE_H - BORDER)) begin

                            red   = 1'b1;
                            green = 1'b1;
                            blue  = 1'b0;

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

                            red   = 1'b1;
                            green = 1'b1;
                            blue  = 1'b1;

                        end
                        else if (digit_on) begin

                            red   = 1'b1;
                            green = 1'b1;
                            blue  = 1'b1;

                        end

                    end

                end

            end


            /* =================================================
               TEXT
               ================================================= */

            else if (inside_any_text && font_pixel) begin

                red   = 1'b1;
                green = 1'b1;
                blue  = 1'b1;

            end

        end

    end


    /* =========================================================
       OUTPUT PINS
       ========================================================= */

    assign uo_out[7] = hsync;
    assign uo_out[3] = vsync;

    assign uo_out[6] = red;
    assign uo_out[5] = green;
    assign uo_out[4] = blue;

    assign uo_out[2] = red;
    assign uo_out[1] = green;
    assign uo_out[0] = blue;

endmodule
