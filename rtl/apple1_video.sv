// Text video for the Apple I core: 40x24 characters, 8x8 font, 3x scale = 960x576 centred in 1280x720 (x 160..1119, y 72..647).
// One glyph row is prefetched a cell ahead (24 pixel clocks per cell). Output `px` is 1 for a foreground pixel.
module apple1_video #(parameter string FONT_FILE = "rom/font8x8.hex") (
    input  logic        clk,
    input  logic [10:0] cx,
    input  logic [9:0]  cy,
    input  logic [9:0]  top40,         // text RAM offset of the first screen line (from the CPU domain)
    output logic [9:0]  vaddr,
    input  logic [6:0]  vq,
    output logic        active,
    output logic        px
);
    localparam int X0 = 157;           // pixel P0 appears at cx = X0 + 2 (two output registers on the pixel path), plus one in the top-level rgb register
    logic [7:0] font [0:1023];
    initial $readmemh(FONT_FILE, font);
    logic [9:0] faddr; logic [7:0] fq;
    always_ff @(posedge clk) fq <= font[faddr];

    logic [9:0] top_v, rowbase;
    logic [1:0] sy; logic [2:0] py; logic vact;
    logic [4:0] cc; logic [5:0] k;       // cc: clock in cell, k: cell being prefetched
    logic [7:0] cur_g, next_g; logic [6:0] ch;
    logic hrun, hact;
    logic [1:0] sx; logic [2:0] pxi;

    function automatic logic [9:0] wrap(input logic [10:0] v); wrap = (v >= 11'd960) ? (v - 11'd960) : v[9:0]; endfunction

    always_ff @(posedge clk) begin
        // ---- vertical state, updated at the start of every line ----
        if (cx == 11'd0) begin
            if (cy == 10'd71) top_v <= top40;
            if (cy == 10'd72) begin vact <= 1'b1; sy <= 0; py <= 0; rowbase <= top_v; end
            else if (cy == 10'd648) vact <= 1'b0;
            else if (vact) begin
                if (sy == 2'd2) begin
                    sy <= 0;
                    if (py == 3'd7) begin py <= 0; rowbase <= wrap({1'b0, rowbase} + 11'd40); end
                    else py <= py + 3'd1;
                end else sy <= sy + 2'd1;
            end
        end
        // ---- horizontal: cell pipeline runs from X0-24 to X0+960 ----
        if (cx == X0 - 24) begin hrun <= 1'b1; cc <= 0; k <= 0; end
        else if (cx == X0 + 960) hrun <= 1'b0;
        else if (hrun) begin
            cc <= (cc == 5'd23) ? 5'd0 : cc + 5'd1;
            if (cc == 5'd23) k <= k + 6'd1;
        end
        if (hrun) begin
            if (cc == 5'd0 && k < 6'd40) vaddr <= rowbase + {4'd0, k};
            if (cc == 5'd2)  ch <= vq;
            if (cc == 5'd3)  faddr <= {ch, py};
            if (cc == 5'd6)  next_g <= fq;
            if (cc == 5'd23 && k < 6'd40) cur_g <= next_g;
        end
        // ---- pixels: bit index = clock in cell / 3 ----
        if (cx == X0) begin hact <= vact; sx <= 0; pxi <= 0; end
        else if (cx > X0 && cx < X0 + 960) begin
            if (sx == 2'd2) begin sx <= 0; pxi <= pxi + 3'd1; end else sx <= sx + 2'd1;
        end
        active <= hact && (cx > X0) && (cx <= X0 + 960) && vact;
        px <= cur_g[3'd7 - pxi];
    end
endmodule
