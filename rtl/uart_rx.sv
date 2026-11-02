module uart_rx #(parameter int DIV = 234) (
    input  logic clk, rx,
    output logic [7:0] data, output logic valid
);
    logic [1:0] sync = 2'b11; logic [11:0] c = 0; logic [3:0] n = 0; logic [7:0] sh = 0;
    always_ff @(posedge clk) begin
        sync <= {sync[0], rx}; valid <= 1'b0;
        if (n == 0) begin
            if (!sync[1]) begin n <= 4'd9; c <= DIV + DIV/2 - 1; end    // start bit seen: sample in the middle of bit 0
        end else if (c == 0) begin
            c <= DIV - 1; n <= n - 4'd1;
            if (n == 4'd1) begin if (sync[1]) begin data <= sh; valid <= 1'b1; end end   // stop bit
            else sh <= {sync[1], sh[7:1]};
        end else c <= c - 12'd1;
    end
endmodule
