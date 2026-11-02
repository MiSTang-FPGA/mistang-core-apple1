// 6502 CPU for MiSTang. Original implementation: documented NMOS behaviour incl. decimal mode and the JMP (ind) page bug;
// unofficial opcodes are 1-byte NOPs. Not cycle exact. No NMI/IRQ (BRK/RTI work).
// Bus: `addr`/`we`/`dout` are presented for one `ce` step; `din` must carry the byte of the address presented in the
// previous step (synchronous memory), so a read takes two steps.
module cpu6502 (
    input  logic        clk, rst, ce,
    output logic [15:0] addr,
    output logic        we,
    output logic [7:0]  dout,
    input  logic [7:0]  din,
    output logic [15:0] dbg_pc,
    output logic [7:0]  dbg_a, dbg_x, dbg_y, dbg_s, dbg_p
);
    typedef enum logic [5:0] {
        S_V0, S_V1, S_V2,                 // vector fetch (reset / BRK)
        S_F0, S_F1, S_DEC,                // opcode fetch, decode
        S_A1I, S_A1L, S_A2I, S_A2L,       // operand bytes
        S_P1I, S_P1L, S_P2I, S_P2L,       // pointer bytes (indirect)
        S_RDI, S_RDL, S_MOD, S_WR,        // effective-address read / modify / write
        S_BR,                             // branch
        S_PUSH, S_PL0, S_PLI, S_PLL       // stack
    } st_t;
    st_t s, nxt;

    typedef enum logic [3:0] {C_PLA, C_PLP, C_RTS_LO, C_RTS_HI, C_RTI_P, C_RTI_LO, C_RTI_HI} pc_t;
    pc_t pcont;
    typedef enum logic [3:0] {N_NONE, N_JSR2, N_JSR3, N_BRK2, N_BRK3, N_BRK4} nk_t;   // what follows a push
    nk_t nk;

    logic [7:0] A, X, Y, S;
    logic [15:0] PC, ea, vec;
    logic fN, fV, fD, fI, fZ, fC;
    logic [7:0] op, lo, hi, dat;
    logic jsr;

    wire [1:0] cc  = op[1:0];
    wire [2:0] bbb = op[4:2];
    wire [2:0] aaa = op[7:5];

    typedef enum logic [3:0] {M_IMP, M_IMM, M_ZP, M_ZPX, M_ZPY, M_ABS, M_ABX, M_ABY, M_INX, M_INY, M_IND} mode_t;
    typedef enum logic [1:0] {K_NONE, K_READ, K_WRITE, K_RMW} kind_t;
    mode_t  mode;
    kind_t  kind;
    logic   is_branch, is_special;
    always_comb begin
        mode = M_IMP; kind = K_NONE; is_branch = 0; is_special = 0;
        if (op[4:0] == 5'b10000) is_branch = 1;
        else if (op == 8'h00 || op == 8'h20 || op == 8'h40 || op == 8'h60 || op == 8'h08 || op == 8'h28 || op == 8'h48 || op == 8'h68) is_special = 1;
        else if (op == 8'h4C) mode = M_ABS;
        else if (op == 8'h6C) mode = M_IND;
        else case (cc)
            2'b01: begin
                case (bbb) 0: mode = M_INX; 1: mode = M_ZP; 2: mode = M_IMM; 3: mode = M_ABS; 4: mode = M_INY; 5: mode = M_ZPX; 6: mode = M_ABY; default: mode = M_ABX; endcase
                if (aaa == 3'd4) kind = K_WRITE; else kind = K_READ;
                if (aaa == 3'd4 && bbb == 3'd2) begin mode = M_IMP; kind = K_NONE; end   // no STA #imm
            end
            2'b10: begin
                case (bbb) 0: mode = M_IMM; 1: mode = M_ZP; 3: mode = M_ABS; 5: mode = M_ZPX; 7: mode = M_ABX; default: mode = M_IMP; endcase
                if ((aaa == 3'd4 || aaa == 3'd5) && bbb == 3'd5) mode = M_ZPY;
                if ((aaa == 3'd4 || aaa == 3'd5) && bbb == 3'd7) mode = M_ABY;
                if (mode != M_IMP) begin
                    if (aaa == 3'd4) kind = K_WRITE; else if (aaa == 3'd5) kind = K_READ; else kind = K_RMW;
                    if (bbb == 3'd0 && aaa != 3'd5) begin mode = M_IMP; kind = K_NONE; end   // only LDX has #imm
                    if (aaa == 3'd4 && bbb == 3'd7) begin mode = M_IMP; kind = K_NONE; end   // SHX: unofficial
                end
            end
            2'b00: begin
                case (bbb) 0: mode = M_IMM; 1: mode = M_ZP; 3: mode = M_ABS; 5: mode = M_ZPX; 7: mode = M_ABX; default: mode = M_IMP; endcase
                case (aaa)
                    3'd1: begin if (bbb == 3'd1 || bbb == 3'd3) kind = K_READ; else mode = M_IMP; end             // BIT
                    3'd4: begin if (bbb == 3'd1 || bbb == 3'd3 || bbb == 3'd5) kind = K_WRITE; else mode = M_IMP; end // STY
                    3'd5: begin kind = K_READ; end                                                                  // LDY
                    3'd6, 3'd7: begin if (bbb == 3'd0 || bbb == 3'd1 || bbb == 3'd3) kind = K_READ; else mode = M_IMP; end // CPY, CPX
                    default: mode = M_IMP;
                endcase
                if (kind == K_NONE) mode = M_IMP;
            end
            default: ;
        endcase
    end

    wire [7:0] P_push = {fN, fV, 2'b11, fD, fI, fZ, fC};
    assign dbg_pc = PC; assign dbg_a = A; assign dbg_x = X; assign dbg_y = Y; assign dbg_s = S;
    assign dbg_p = {fN, fV, 2'b11, fD, fI, fZ, fC};

    always_comb begin
        addr = PC; we = 1'b0; dout = 8'h00;
        case (s)
            S_V0: addr = vec;
            S_V1: addr = vec + 16'd1;
            S_A1I, S_A2I: addr = PC;
            S_P1I: addr = ea;
            S_P2I: addr = {ea[15:8], ea[7:0] + 8'd1};
            S_RDI: addr = ea;
            S_WR: begin addr = ea; we = 1'b1; dout = dat; end
            S_PUSH: begin addr = {8'h01, S}; we = 1'b1; dout = dat; end
            S_PLI: addr = {8'h01, S};
            default: addr = PC;
        endcase
    end

    task automatic setnz(input [7:0] v); fN <= v[7]; fZ <= (v == 8'h00); endtask
    task automatic go_ea(input [15:0] e);
        ea <= e;
        case (kind)
            K_READ, K_RMW: s <= S_RDI;
            K_WRITE: begin
                s <= S_WR;
                dat <= (cc == 2'b01) ? A : (cc == 2'b10) ? X : Y;
            end
            default: begin PC <= e; s <= S_F0; end   // JMP abs
        endcase
    endtask

    logic [8:0] t9; logic [7:0] r8, v8; logic [4:0] alo; logic [9:0] ahi; logic signed [9:0] sa, sb;
    always_ff @(posedge clk) begin
        if (rst) begin
            s <= S_V0; vec <= 16'hFFFC; S <= 8'hFD; fI <= 1; fD <= 0; A <= 0; X <= 0; Y <= 0; fN <= 0; fV <= 0; fZ <= 0; fC <= 0; PC <= 0; jsr <= 0;
        end else if (ce) begin
            case (s)
                S_V0: s <= S_V1;
                S_V1: begin lo <= din; s <= S_V2; end
                S_V2: begin PC <= {din, lo}; s <= S_F0; end
                S_F0: s <= S_F1;
                S_F1: begin op <= din; PC <= PC + 16'd1; s <= S_DEC; end
                S_DEC: begin
                    jsr <= 0;
                    if (is_branch) s <= S_A1I;
                    else if (is_special) begin
                        case (op)
                            8'h48: begin dat <= A; nk <= N_NONE; s <= S_PUSH; end
                            8'h08: begin dat <= P_push; nk <= N_NONE; s <= S_PUSH; end
                            8'h68: begin pcont <= C_PLA; s <= S_PL0; end
                            8'h28: begin pcont <= C_PLP; s <= S_PL0; end
                            8'h20: begin jsr <= 1; s <= S_A1I; end
                            8'h60: begin pcont <= C_RTS_LO; s <= S_PL0; end
                            8'h40: begin pcont <= C_RTI_P; s <= S_PL0; end
                            default: begin   // BRK
                                PC <= PC + 16'd1; dat <= (PC + 16'd1) >> 8; nk <= N_BRK2; s <= S_PUSH;
                            end
                        endcase
                    end else if (mode == M_IMP) begin
                        s <= S_F0;
                        case (op)
                            8'h18: fC <= 0; 8'h38: fC <= 1; 8'h58: fI <= 0; 8'h78: fI <= 1; 8'hB8: fV <= 0; 8'hD8: fD <= 0; 8'hF8: fD <= 1;
                            8'h88: begin Y <= Y - 8'd1; setnz(Y - 8'd1); end
                            8'hC8: begin Y <= Y + 8'd1; setnz(Y + 8'd1); end
                            8'hE8: begin X <= X + 8'd1; setnz(X + 8'd1); end
                            8'hCA: begin X <= X - 8'd1; setnz(X - 8'd1); end
                            8'hA8: begin Y <= A; setnz(A); end
                            8'hAA: begin X <= A; setnz(A); end
                            8'h98: begin A <= Y; setnz(Y); end
                            8'h8A: begin A <= X; setnz(X); end
                            8'hBA: begin X <= S; setnz(S); end
                            8'h9A: S <= X;
                            8'h0A: begin A <= {A[6:0], 1'b0}; fC <= A[7]; setnz({A[6:0], 1'b0}); end
                            8'h2A: begin A <= {A[6:0], fC};   fC <= A[7]; setnz({A[6:0], fC}); end
                            8'h4A: begin A <= {1'b0, A[7:1]}; fC <= A[0]; setnz({1'b0, A[7:1]}); end
                            8'h6A: begin A <= {fC, A[7:1]};   fC <= A[0]; setnz({fC, A[7:1]}); end
                            default: ;
                        endcase
                    end else if (mode == M_IMM) begin
                        ea <= PC; PC <= PC + 16'd1; s <= S_RDI;
                    end else s <= S_A1I;
                end
                S_A1I: s <= S_A1L;
                S_A1L: begin
                    lo <= din;
                    PC <= PC + 16'd1;
                    if (is_branch) s <= S_BR;
                    else if (jsr) begin dat <= (PC + 16'd1) >> 8; nk <= N_JSR2; s <= S_PUSH; end   // PC = address of the high operand byte: pushed as the return address
                    else case (mode)
                        M_ZP:  go_ea({8'h00, din});
                        M_ZPX: go_ea({8'h00, din + X});
                        M_ZPY: go_ea({8'h00, din + Y});
                        M_INX: begin ea <= {8'h00, din + X}; s <= S_P1I; end
                        M_INY: begin ea <= {8'h00, din};     s <= S_P1I; end
                        default: s <= S_A2I;
                    endcase
                end
                S_A2I: s <= S_A2L;
                S_A2L: begin
                    hi <= din; PC <= PC + 16'd1;
                    if (jsr) begin PC <= {din, lo}; s <= S_F0; end
                    else case (mode)
                        M_ABS: go_ea({din, lo});
                        M_ABX: go_ea({din, lo} + {8'h00, X});
                        M_ABY: go_ea({din, lo} + {8'h00, Y});
                        M_IND: begin ea <= {din, lo}; s <= S_P1I; end
                        default: s <= S_F0;
                    endcase
                end
                S_P1I: s <= S_P1L;
                S_P1L: begin lo <= din; s <= S_P2I; end
                S_P2I: s <= S_P2L;
                S_P2L: begin
                    if (mode == M_IND) begin PC <= {din, lo}; s <= S_F0; end
                    else if (mode == M_INY) go_ea({din, lo} + {8'h00, Y});
                    else go_ea({din, lo});
                end
                S_RDI: s <= S_RDL;
                S_RDL: begin
                    dat <= din;
                    if (kind == K_RMW) s <= S_MOD;
                    else begin
                        s <= S_F0;
                        case (cc)
                            2'b01: case (aaa)
                                3'd0: begin A <= A | din; setnz(A | din); end
                                3'd1: begin A <= A & din; setnz(A & din); end
                                3'd2: begin A <= A ^ din; setnz(A ^ din); end
                                3'd5: begin A <= din; setnz(din); end
                                3'd6: begin t9 = {1'b0, A} - {1'b0, din}; fC <= (A >= din); setnz(t9[7:0]); end
                                3'd3: begin   // ADC
                                    t9 = {1'b0, A} + {1'b0, din} + {8'b0, fC};
                                    if (!fD) begin A <= t9[7:0]; fC <= t9[8]; setnz(t9[7:0]); fV <= (~(A ^ din) & (A ^ t9[7:0])) >> 7; end
                                    else begin
                                        alo = {1'b0, A[3:0]} + {1'b0, din[3:0]} + {4'b0, fC};
                                        if (alo >= 5'd10) alo = ((alo + 5'd6) & 5'h0F) + 5'd16;
                                        ahi = {2'b0, A[7:4], 4'b0} + {2'b0, din[7:4], 4'b0} + {5'b0, alo};
                                        sa = $signed({{2{A[7]}}, A[7:4], 4'b0}) + $signed({{2{din[7]}}, din[7:4], 4'b0}) + $signed({5'b0, alo});
                                        fN <= ahi[7]; fV <= (sa < -10'sd128) || (sa > 10'sd127); fZ <= (t9[7:0] == 8'h00);
                                        if (ahi >= 10'd160) ahi = ahi + 10'd96;
                                        A <= ahi[7:0]; fC <= (ahi >= 10'd256);
                                    end
                                end
                                3'd7: begin   // SBC
                                    t9 = {1'b0, A} + {1'b0, ~din} + {8'b0, fC};
                                    fC <= t9[8]; fV <= ((A ^ din) & (A ^ t9[7:0])) >> 7; setnz(t9[7:0]);
                                    if (!fD) A <= t9[7:0];
                                    else begin
                                        sa = $signed({6'b0, A[3:0]}) - $signed({6'b0, din[3:0]}) + (fC ? 10'sd0 : -10'sd1);
                                        if (sa < 0) sa = (((sa - 10'sd6) & 10'sd15)) - 10'sd16;
                                        sb = $signed({2'b0, A[7:4], 4'b0}) - $signed({2'b0, din[7:4], 4'b0}) + sa;
                                        if (sb < 0) sb = sb - 10'sd96;
                                        A <= sb[7:0];
                                    end
                                end
                                default: ;
                            endcase
                            2'b10: if (aaa == 3'd5) begin X <= din; setnz(din); end
                            2'b00: case (aaa)
                                3'd1: begin fZ <= ((A & din) == 8'h00); fN <= din[7]; fV <= din[6]; end
                                3'd5: begin Y <= din; setnz(din); end
                                3'd6: begin t9 = {1'b0, Y} - {1'b0, din}; fC <= (Y >= din); setnz(t9[7:0]); end
                                3'd7: begin t9 = {1'b0, X} - {1'b0, din}; fC <= (X >= din); setnz(t9[7:0]); end
                                default: ;
                            endcase
                            default: ;
                        endcase
                    end
                end
                S_MOD: begin
                    case (aaa)
                        3'd0: begin v8 = {dat[6:0], 1'b0}; fC <= dat[7]; end
                        3'd1: begin v8 = {dat[6:0], fC};   fC <= dat[7]; end
                        3'd2: begin v8 = {1'b0, dat[7:1]}; fC <= dat[0]; end
                        3'd3: begin v8 = {fC, dat[7:1]};   fC <= dat[0]; end
                        3'd6: v8 = dat - 8'd1;
                        default: v8 = dat + 8'd1;
                    endcase
                    dat <= v8; setnz(v8); s <= S_WR;
                end
                S_WR: s <= S_F0;
                S_BR: begin
                    case (op[7:6])
                        2'b00: r8 = {7'b0, (op[5] == fN)};
                        2'b01: r8 = {7'b0, (op[5] == fV)};
                        2'b10: r8 = {7'b0, (op[5] == fC)};
                        default: r8 = {7'b0, (op[5] == fZ)};
                    endcase
                    if (r8[0]) PC <= PC + {{8{lo[7]}}, lo};
                    s <= S_F0;
                end
                S_PUSH: begin
                    S <= S - 8'd1;
                    case (nk)
                        N_NONE: s <= S_F0;
                        N_JSR2: begin dat <= PC[7:0]; nk <= N_JSR3; s <= S_PUSH; end
                        N_JSR3: s <= S_A2I;
                        N_BRK2: begin dat <= PC[7:0]; nk <= N_BRK3; s <= S_PUSH; end
                        N_BRK3: begin dat <= P_push; nk <= N_BRK4; s <= S_PUSH; end
                        default: begin fI <= 1; vec <= 16'hFFFE; s <= S_V0; end
                    endcase
                end
                S_PL0: begin S <= S + 8'd1; s <= S_PLI; end
                S_PLI: s <= S_PLL;
                S_PLL: begin
                    case (pcont)
                        C_PLA: begin A <= din; setnz(din); s <= S_F0; end
                        C_PLP: begin fN <= din[7]; fV <= din[6]; fD <= din[3]; fI <= din[2]; fZ <= din[1]; fC <= din[0]; s <= S_F0; end
                        C_RTS_LO: begin lo <= din; pcont <= C_RTS_HI; s <= S_PL0; end
                        C_RTS_HI: begin PC <= {din, lo} + 16'd1; s <= S_F0; end
                        C_RTI_P: begin fN <= din[7]; fV <= din[6]; fD <= din[3]; fI <= din[2]; fZ <= din[1]; fC <= din[0]; pcont <= C_RTI_LO; s <= S_PL0; end
                        C_RTI_LO: begin lo <= din; pcont <= C_RTI_HI; s <= S_PL0; end
                        default: begin PC <= {din, lo}; s <= S_F0; end
                    endcase
                end
                default: s <= S_F0;
            endcase
        end
    end
endmodule
