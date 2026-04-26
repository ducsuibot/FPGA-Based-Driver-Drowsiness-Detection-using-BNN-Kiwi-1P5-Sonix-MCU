`timescale 1ns / 1ps

module datapath_core (
    input  wire        clk, rst_n,
    input  wire        valid_in, acc_clr, is_acc_done,
    input  wire        is_conv, 
    input  wire [15:0] window_in, wgt_data, thresh_val,
    output reg         out_bit, valid_out,
    output wire [11:0] current_pop   
);
    wire [15:0] x = ~(window_in ^ wgt_data);
    
    // CONV dùng 9 bit, FC dùng 16 bit
    wire [15:0] masked_x = is_conv ? (x & 16'h01FF) : x; 

    wire [4:0] pop_cnt = masked_x[0]  + masked_x[1]  + masked_x[2]  + masked_x[3]  + 
                         masked_x[4]  + masked_x[5]  + masked_x[6]  + masked_x[7]  + 
                         masked_x[8]  + masked_x[9]  + masked_x[10] + masked_x[11] + 
                         masked_x[12] + masked_x[13] + masked_x[14] + masked_x[15];
                         
    reg [11:0] acc_reg;
    reg valid_d1, is_acc_done_d1;
    reg [15:0] thresh_reg; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_reg <= 0; valid_d1 <= 0; is_acc_done_d1 <= 0; thresh_reg <= 0;
        end else begin
            valid_d1 <= valid_in;
            is_acc_done_d1 <= is_acc_done;
            
            if (valid_in) begin
                acc_reg <= acc_clr ? {7'd0, pop_cnt} : (acc_reg + pop_cnt);
            end
            
            // TRẢ LẠI BẢN GỐC: Chốt Threshold ở nhịp is_acc_done (Nhịp thứ 16)
            if (is_acc_done) begin
                thresh_reg <= thresh_val; 
            end
        end
    end

    // =========================================================================
    // SỬA LỖI POLARITY Ở ĐÂY: Phân luồng logic cực kỳ an toàn
    // - is_conv = 1 (Lớp CONV/POOL): Dùng logic cũ (<)
    // - is_conv = 0 (Lớp FC): Dùng logic mới (<=) khớp với Python Golden
    // =========================================================================
    // SỬA: Đổi < thành <= để khớp hoàn toàn với logic file C
    wire bn_out = is_conv ? 
                  (thresh_reg[15] ? (acc_reg >= thresh_reg[14:0]) : (acc_reg <= thresh_reg[14:0])) :
                  (thresh_reg[15] ? (acc_reg >= thresh_reg[14:0]) : (acc_reg <= thresh_reg[14:0]));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin out_bit <= 0; valid_out <= 0; end 
        else begin
            valid_out <= (valid_d1 && is_acc_done_d1); 
            out_bit   <= bn_out;
        end
    end
    assign current_pop = acc_reg;
endmodule