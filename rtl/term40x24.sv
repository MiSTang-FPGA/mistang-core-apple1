// 40x24 text terminal controller for MiSTang Apple I. Original implementation.
// Writes characters into a text RAM used as a ring of 24 lines (`top40` = RAM offset of the first screen line).
// Handles CR (newline), BS (erase left), printable 0x20..0x7E, scrolling.
module term40x24 (
    input  logic       clk, rst,
    input  logic       wr,
    input  logic [6:0] ch,
    output logic [9:0] waddr,
    output logic [6:0] wdata,
    output logic       we,
    output logic [9:0] top40,
    output logic       busy
);
    typedef enum logic [1:0] {T_CLR, T_IDLE, T_LINE} t_t;
    t_t st;
    logic [5:0] x; logic [4:0] y; logic [9:0] cbase, cnt;
    assign busy = (st != T_IDLE);

    function automatic logic [9:0] wrap(input logic [10:0] v);
        wrap = (v >= 11'd960) ? (v - 11'd960) : v[9:0];
    endfunction

    task automatic newline();
        x <= 0;
        cbase <= wrap({1'b0, cbase} + 11'd40);
        if (y == 5'd23) begin
            top40 <= wrap({1'b0, top40} + 11'd40);
            cnt <= 0; st <= T_LINE;
        end else y <= y + 5'd1;
    endtask

    always_ff @(posedge clk) begin
        we <= 1'b0;
        if (rst) begin
            st <= T_CLR; cnt <= 0; x <= 0; y <= 0; cbase <= 0; top40 <= 0;
        end else case (st)
            T_CLR: begin
                waddr <= cnt; wdata <= 7'h20; we <= 1'b1; cnt <= cnt + 10'd1;
                if (cnt == 10'd959) st <= T_IDLE;
            end
            T_LINE: begin
                waddr <= cbase + cnt; wdata <= 7'h20; we <= 1'b1; cnt <= cnt + 10'd1;
                if (cnt == 10'd39) st <= T_IDLE;
            end
            default: if (wr) begin
                if (ch == 7'h0D) newline();
                else if (ch == 7'h08) begin
                    if (x != 0) begin x <= x - 6'd1; waddr <= cbase + {4'd0, x} - 10'd1; wdata <= 7'h20; we <= 1'b1; end
                end else if (ch >= 7'h20 && ch < 7'h7F) begin
                    waddr <= cbase + {4'd0, x}; wdata <= ch; we <= 1'b1;
                    if (x == 6'd39) newline(); else x <= x + 6'd1;
                end
            end
        endcase
    end
endmodule
