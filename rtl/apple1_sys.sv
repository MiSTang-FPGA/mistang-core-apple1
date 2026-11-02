// Apple I system: 6502, 4 KiB RAM, 4 KiB monitor ROM at $F000, keyboard/display port at $D010..$D013, 40x24 terminal.
module apple1_sys #(parameter int CE_DIV = 4, parameter int UART_DIV = 234, parameter int DSP_BUSY = 3000, parameter string ROM_FILE = "rom/monitor.hex") (
    input  logic       clk, rst,
    input  logic       rx,
    // text RAM read port for the video (own clock)
    input  logic       vclk,
    input  logic [9:0] vaddr,
    output logic [6:0] vq,
    output logic [9:0] top40,
    // second read port on the CPU clock (UART screenshot)
    input  logic [9:0] cap_addr,
    output logic [6:0] cap_q
);
    // ---- CPU ----
    logic [15:0] addr; logic we; logic [7:0] dout, din, din_now;
    logic ce; logic [7:0] cec = 0;
    always_ff @(posedge clk) begin ce <= (cec == CE_DIV - 1); cec <= (cec == CE_DIV - 1) ? 8'd0 : cec + 8'd1; end
    cpu6502 cpu (.clk(clk), .rst(rst), .ce(ce), .addr(addr), .we(we), .dout(dout), .din(din),
                 .dbg_pc(), .dbg_a(), .dbg_x(), .dbg_y(), .dbg_s(), .dbg_p());

    // ---- memories ----
    logic [7:0] ram [0:4095]; logic [7:0] rom [0:4095];
    initial begin $readmemh(ROM_FILE, rom); $readmemh("rom/zeros4k.hex", ram); end
    logic [7:0] ram_q, rom_q;
    wire is_ram = (addr[15:12] == 4'h0);
    wire is_rom = (addr[15:12] == 4'hF);
    wire is_io  = (addr[15:2] == 14'h3404);          // $D010..$D013
    always_ff @(posedge clk) begin
        if (we && is_ram) ram[addr[11:0]] <= dout;
        ram_q <= ram[addr[11:0]];
        rom_q <= rom[addr[11:0]];
    end

    // ---- keyboard ----
    logic [7:0] rxd; logic rxv;
    uart_rx #(.DIV(UART_DIV)) u_rx (.clk(clk), .rx(rx), .data(rxd), .valid(rxv));
    logic [6:0] kbd; logic kbd_rdy = 0;
    wire [6:0] rxu = (rxd[6:0] >= 7'h61 && rxd[6:0] <= 7'h7A) ? (rxd[6:0] - 7'h20) : (rxd[6:0] == 7'h0A ? 7'h0D : rxd[6:0]);
    always_ff @(posedge clk) begin
        if (rxv) begin kbd <= rxu; kbd_rdy <= 1'b1; end
        else if (ce && !we && is_io && addr[1:0] == 2'b00) kbd_rdy <= 1'b0;     // reading $D010 clears the flag
    end

    // ---- display ----
    logic [15:0] dsp_busy = 0; logic t_wr = 0; logic [6:0] t_ch; logic [9:0] t_waddr; logic [6:0] t_wdata; logic t_we; logic t_busy;
    always_ff @(posedge clk) begin
        t_wr <= 1'b0;
        if (rst) dsp_busy <= 0;
        else if (ce && we && is_io && addr[1:0] == 2'b10) begin t_wr <= 1'b1; t_ch <= dout[6:0]; dsp_busy <= DSP_BUSY; end
        else if (dsp_busy != 0) dsp_busy <= dsp_busy - 16'd1;
    end
    term40x24 term (.clk(clk), .rst(rst), .wr(t_wr), .ch(t_ch), .waddr(t_waddr), .wdata(t_wdata), .we(t_we), .top40(top40), .busy(t_busy));
    logic [6:0] text [0:1023];
    always_ff @(posedge clk) if (t_we) text[t_waddr] <= t_wdata;
    always_ff @(posedge vclk) vq <= text[vaddr];
    always_ff @(posedge clk) cap_q <= text[cap_addr];

    // ---- bus mux (data of the address presented in the previous clock) ----
    logic [7:0] io_q; logic [2:0] sel_q;
    always_ff @(posedge clk) begin
        sel_q <= {is_io, is_rom, is_ram};
        case (addr[1:0])
            2'b00: io_q <= {1'b1, kbd};
            2'b01: io_q <= {kbd_rdy, 7'h00};
            2'b10: io_q <= {(dsp_busy != 0) | t_busy, 7'h00};
            default: io_q <= 8'h00;
        endcase
    end
    always_comb begin
        din_now = 8'h00;
        if (sel_q[0]) din_now = ram_q; else if (sel_q[1]) din_now = rom_q; else if (sel_q[2]) din_now = io_q;
    end
    // the CPU wants the byte of the address of the PREVIOUS step: hold what the memory returned during the last clock of that step
    // (needs CE_DIV >= 2: one clock of memory latency)
    always_ff @(posedge clk) if (ce) din <= din_now;
endmodule
