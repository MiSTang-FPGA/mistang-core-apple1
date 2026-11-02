// MiSTang Apple I: 720p60 HDMI text screen (40x24, 3x), keyboard and screenshot over the board's USB-UART.
module apple1_top (
    input  logic       sys_clk,
    output logic [1:0] led,
    output logic       uart_tx,
    input  logic       uart_rx,
    output logic       tmds_clk_p, tmds_clk_n,
    output logic [2:0] tmds_d_p, tmds_d_n
);
    logic clk_p5, clk_p, hdmi_lock;
    pll_hdmi u_pll (.clock_in(sys_clk), .clock_out(clk_p5), .locked(hdmi_lock));
    CLKDIV #(.DIV_MODE("5")) u_div5 (.CLKOUT(clk_p), .HCLKIN(clk_p5), .RESETN(hdmi_lock), .CALIB(1'b0));
    logic [3:0] rst_cnt = 0; logic reset = 1;
    always_ff @(posedge clk_p) begin
        if (!hdmi_lock) rst_cnt <= 0; else if (rst_cnt != 4'hf) rst_cnt <= rst_cnt + 1'd1;
        reset <= rst_cnt != 4'hf;
    end
    logic [7:0] g_rst_cnt = 0; logic g_rst = 1;
    always_ff @(posedge sys_clk) begin if (g_rst_cnt != 8'hff) g_rst_cnt <= g_rst_cnt + 1'd1; g_rst <= (g_rst_cnt != 8'hff); end

    logic [10:0] cx; logic [9:0] cy; logic [23:0] rgb;
    logic [9:0] vaddr, top40, cap_addr; logic [6:0] vq, cap_q;
    apple1_sys #(.CE_DIV(4), .UART_DIV(234), .DSP_BUSY(3000)) u_sys (
        .clk(sys_clk), .rst(g_rst), .rx(uart_rx), .vclk(clk_p), .vaddr(vaddr), .vq(vq), .top40(top40),
        .cap_addr(cap_addr), .cap_q(cap_q));
    logic active, px;
    apple1_video u_vid (.clk(clk_p), .cx(cx), .cy(cy), .top40(top40), .vaddr(vaddr), .vq(vq), .active(active), .px(px));
    always_ff @(posedge clk_p) rgb <= !active ? 24'h000000 : px ? 24'hE8E8E8 : 24'h0B0B0B;

    logic [2:0] tmds; logic tmds_clock; logic [15:0] silence [1:0];
    initial begin silence[0] = 0; silence[1] = 0; end
    logic [10:0] aud_div = 0; logic clk_audio = 0;
    always_ff @(posedge clk_p) if (aud_div == 11'd773) begin aud_div <= 0; clk_audio <= ~clk_audio; end else aud_div <= aud_div + 1'd1;
    hdmi #(.VIDEO_ID_CODE(4), .DVI_OUTPUT(0), .VIDEO_REFRESH_RATE(60.0), .AUDIO_RATE(48000), .AUDIO_BIT_WIDTH(16),
           .VENDOR_NAME({"MiSTang", 8'd0}), .PRODUCT_DESCRIPTION({"TangNano20K", 40'd0})) u_hdmi (
        .clk_pixel_x5(clk_p5), .clk_pixel(clk_p), .clk_audio(clk_audio), .reset(reset),
        .rgb(rgb), .audio_sample_word(silence), .tmds(tmds), .tmds_clock(tmds_clock),
        .cx(cx), .cy(cy), .frame_width(), .frame_height(), .screen_width(), .screen_height());
    TLVDS_OBUF u_obuf [3:0] (.I({tmds_clock, tmds}), .O({tmds_clk_p, tmds_d_p}), .OB({tmds_clk_n, tmds_d_n}));

    // UART screenshot: "APL1", top40 (hi, lo), then the 960 text RAM bytes
    logic [7:0] tx_data; logic tx_start, tx_busy;
    uart_tx #(.DIV(234)) u_tx (.clk(sys_clk), .data(tx_data), .start(tx_start), .busy(tx_busy), .tx(uart_tx));
    typedef enum logic [2:0] {U_HDR, U_T0, U_T1, U_RD, U_LAT, U_SEND} u_t; u_t us = U_HDR;
    logic [2:0] hi = 0; logic [9:0] ai = 0; logic [1:0] lat = 0; logic [9:0] top_s = 0;
    wire tx_ready = !tx_busy && !tx_start;
    always_ff @(posedge sys_clk) begin
        tx_start <= 1'b0;
        case (us)
            U_HDR: if (tx_ready) begin
                if (hi == 0) top_s <= top40;
                tx_data <= (hi == 0) ? "A" : (hi == 1) ? "P" : (hi == 2) ? "L" : "1"; tx_start <= 1'b1;
                if (hi == 3) begin hi <= 0; us <= U_T0; end else hi <= hi + 3'd1;
            end
            U_T0: if (tx_ready) begin tx_data <= {6'd0, top_s[9:8]}; tx_start <= 1'b1; us <= U_T1; end
            U_T1: if (tx_ready) begin tx_data <= top_s[7:0]; tx_start <= 1'b1; ai <= 0; us <= U_RD; end
            U_RD: begin cap_addr <= ai; lat <= 0; us <= U_LAT; end
            U_LAT: begin lat <= lat + 2'd1; if (lat == 2'd2) us <= U_SEND; end
            U_SEND: if (tx_ready) begin
                tx_data <= {1'b0, cap_q}; tx_start <= 1'b1; ai <= ai + 10'd1;
                if (ai == 10'd959) us <= U_HDR; else us <= U_RD;
            end
            default: us <= U_HDR;
        endcase
    end
    logic [24:0] hb = 0; always_ff @(posedge sys_clk) hb <= hb + 1'd1;
    assign led = {~hdmi_lock, ~hb[24]};
endmodule
