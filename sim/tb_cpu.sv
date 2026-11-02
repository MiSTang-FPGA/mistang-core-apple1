`timescale 1ns/1ps
module tb_cpu;
    logic clk = 0, rst = 1; always #5 clk = ~clk;
    logic [7:0] mem [0:65535];
    logic [15:0] addr; logic we; logic [7:0] dout, din;
    logic [15:0] pc; logic [7:0] a, x, y, sp, p;
    cpu6502 dut(.clk(clk), .rst(rst), .ce(1'b1), .addr(addr), .we(we), .dout(dout), .din(din), .dbg_pc(pc), .dbg_a(a), .dbg_x(x), .dbg_y(y), .dbg_s(sp), .dbg_p(p));
    always_ff @(posedge clk) begin if (we) mem[addr] <= dout; din <= mem[addr]; end
    integer n = -1, f, i, cyc = 0; reg [5:0] prev;
    initial begin
        $readmemh("build/rand_mem.hex", mem);
        repeat (3) @(posedge clk); rst <= 0;
        prev = 6'd0;
        while (n < `INSTR && cyc < `INSTR * 60) begin
            @(posedge clk); cyc++;
            if (dut.s == dut.S_F0 && prev != dut.S_F0 && !rst) n++;
            prev = dut.s;
        end
        // wait until the instruction in flight completed: stop when the next fetch starts
        f = $fopen("build/rtl_state.txt", "w");
        $fwrite(f, "%04x %02x %02x %02x %02x %02x\n", pc, a, x, y, sp, p);
        for (i = 0; i < 65536; i++) $fwrite(f, "%02x\n", mem[i]);
        $fclose(f); $finish;
    end
endmodule
