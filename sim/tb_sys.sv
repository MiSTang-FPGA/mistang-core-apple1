`timescale 1ns/1ps
module tb_sys;
    parameter int DIV = 16;
    logic clk = 0, rst = 1, rx = 1; always #5 clk = ~clk;
    logic [6:0] vq; logic [9:0] top40;
    apple1_sys #(.CE_DIV(2), .UART_DIV(DIV), .DSP_BUSY(40)) dut (.clk(clk), .rst(rst), .rx(rx), .vclk(clk), .vaddr(10'd0), .vq(vq), .top40(top40), .cap_addr(10'd0), .cap_q());
    reg [7:0] keys [0:1023];
    integer i, b, f, r, c, base;
    initial begin
        $readmemh("sim/keys.hex", keys);
        repeat (6) @(posedge clk); rst <= 0;
        repeat (4000) @(posedge clk);             // let the screen clear and the banner print
        for (i = 0; i < `NKEYS; i++) begin
            rx <= 0; repeat (DIV) @(posedge clk);
            for (b = 0; b < 8; b++) begin rx <= keys[i][b]; repeat (DIV) @(posedge clk); end
            rx <= 1; repeat (DIV) @(posedge clk);
            if (keys[i] == 8'h0D) repeat (`GAPCR) @(posedge clk); else repeat (`GAP) @(posedge clk);
        end
        repeat (60000) @(posedge clk);
        f = $fopen("build/rtl_screen.txt", "w");
        for (r = 0; r < 24; r++) begin
            base = (top40 + r * 40) % 960;
            for (c = 0; c < 40; c++) $fwrite(f, "%c", dut.text[base + c]);
            $fwrite(f, "\n");
        end
        $fclose(f); $finish;
    end
endmodule
