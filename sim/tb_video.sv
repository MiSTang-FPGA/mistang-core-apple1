`timescale 1ns/1ps
module tb_video;
    logic clk = 0; always #5 clk = ~clk;
    logic [10:0] cx = 0; logic [9:0] cy = 0;
    logic [6:0] text [0:959]; logic [6:0] vq; logic [9:0] vaddr; logic active, px;
    apple1_video dut (.clk(clk), .cx(cx), .cy(cy), .top40(10'd400), .vaddr(vaddr), .vq(vq), .active(active), .px(px));
    always_ff @(posedge clk) vq <= text[vaddr];
    always_ff @(posedge clk) begin
        if (cx == 11'd1649) begin cx <= 0; cy <= (cy == 10'd749) ? 10'd0 : cy + 10'd1; end else cx <= cx + 11'd1;
    end
    integer cnt [0:1023]; integer qi; initial for (qi=0;qi<1024;qi++) cnt[qi]=0;
    integer f, frames = 0, xs = 0; reg [959:0] line; integer first_cx = -1;
    initial begin
        $readmemh("build/vid_text.hex", text);
        f = $fopen("build/rtl_video.txt", "w");
    end
    always_ff @(posedge clk) begin
        if (frames == 1) begin       // second frame: the first one loads top_v
            if (active) begin
                cnt[cy] = cnt[cy] + 1; if ((cy==73 || cy==647 || cy==72) && (cx>1115)) $display("cy%0d active cx=%0d", cy, cx);
                if (xs == 0 && first_cx < 0) first_cx = cx;
                $fwrite(f, "%s", px ? "#" : ".");
                xs = xs + 1;
                if (xs == 960) begin $fwrite(f, "\n"); xs = 0; end
            end
        end
        if (cx == 11'd1649 && cy == 10'd749) begin
            frames <= frames + 1;
            if (frames == 1) begin $fclose(f); $display("first active cx=%0d", first_cx); for (qi=0;qi<1024;qi++) if (cnt[qi] != 0 && cnt[qi] != 960) $display("line %0d has %0d active px", qi, cnt[qi]); qi=0; for (qi=0;qi<1024;qi++) if (cnt[qi]!=0) begin $display("first active line %0d", qi); qi=2000; end $finish; end
        end
    end
endmodule
