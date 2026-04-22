`timescale 1ns / 1ps

module padding_and_buffer (
    input  wire        clk, rst_n, spi_we,
    input  wire [6:0]  spi_addr,    
    input  wire [7:0]  spi_data,    
    input  wire [10:0] rd_addr,     
    output wire [15:0] rd_data,     
    input  wire        wr_en,       
    input  wire [10:0] wr_addr,     
    input  wire [15:0] wr_data,
    input  wire        shift_en, is_conv2, is_img_read,    
    input  wire [4:0]  pad_x, pad_y,
    input  wire [4:0]  in_ch, // FIX BUG-M: Đón dây 5-bit
    output wire [15:0] window_out,
    output wire [15:0] center_pixel 
);
    // FIX LỖI 9: Mở rộng RAM lên 2048 để tránh silent wrap-around
    reg [15:0] act_ram [0:2047];

    always @(posedge clk) begin
        if (spi_we) act_ram[spi_addr] <= {8'd0, spi_data};
        else if (wr_en) act_ram[wr_addr] <= wr_data;
    end

    wire [10:0] fetch_addr = is_img_read ? (rd_addr >> 3) : rd_addr;
    wire [2:0]  bit_idx    = is_img_read ? rd_addr[2:0] : 3'd0;
    
    reg [15:0] raw_rd_data;
    reg        is_img_read_d1; // FIX LỖI 12: Đăng ký cờ đọc ảnh
    reg [2:0]  bit_idx_d1;     // FIX LỖI 12: Đăng ký index bit

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            raw_rd_data <= 16'd0;
            is_img_read_d1 <= 1'b0;
            bit_idx_d1 <= 3'd0;
        end else begin
            raw_rd_data <= act_ram[fetch_addr];
            is_img_read_d1 <= is_img_read;
            bit_idx_d1 <= bit_idx;
        end
    end
    
    // Sử dụng tín hiệu đã delay để bóc tách bit
    assign rd_data = is_img_read_d1 ? {15'd0, raw_rd_data[7 - bit_idx_d1]} : raw_rd_data;

    reg [15:0] lb0 [0:23]; reg [15:0] lb1 [0:23];
    reg [15:0] w00, w01, w02, w10, w11, w12, w20, w21, w22;
    wire [4:0] tap = is_conv2 ? 5'd11 : 5'd23;
    integer i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i=0; i<24; i=i+1) begin lb0[i]<=0; lb1[i]<=0; end
            w00<=0; w01<=0; w02<=0; w10<=0; w11<=0; w12<=0; w20<=0; w21<=0; w22<=0;
        end else if (shift_en) begin 
            for (i=23; i>0; i=i-1) begin lb0[i] <= lb0[i-1]; lb1[i] <= lb1[i-1]; end
            lb0[0] <= rd_data; lb1[0] <= lb0[tap];
            w20 <= w21; w21 <= w22; w22 <= rd_data; 
            w10 <= w11; w11 <= w12; w12 <= lb0[tap];   
            w00 <= w01; w01 <= w02; w02 <= lb1[tap];   
        end
    end

    assign center_pixel = w11;
    wire [4:0] max_coord = is_conv2 ? 5'd11 : 5'd23;
    wire pad_left = (pad_x == 0), pad_right = (pad_x == max_coord);
    wire pad_top  = (pad_y == 0), pad_bottom = (pad_y == max_coord);

    wire [8:0] win_1b;
   assign win_1b[8] = (pad_top || pad_left)     ? 1'b0 : (in_ch < 16 ? w00[in_ch[3:0]] : 1'b0);
    assign win_1b[7] = (pad_top)                 ? 1'b0 : (in_ch < 16 ? w01[in_ch[3:0]] : 1'b0);
    assign win_1b[6] = (pad_top || pad_right)    ? 1'b0 : (in_ch < 16 ? w02[in_ch[3:0]] : 1'b0);
    assign win_1b[5] = (pad_left)                ? 1'b0 : (in_ch < 16 ? w10[in_ch[3:0]] : 1'b0);
    assign win_1b[4] =                                    (in_ch < 16 ? w11[in_ch[3:0]] : 1'b0);
    assign win_1b[3] = (pad_right)               ? 1'b0 : (in_ch < 16 ? w12[in_ch[3:0]] : 1'b0);
    assign win_1b[2] = (pad_bottom || pad_left)  ? 1'b0 : (in_ch < 16 ? w20[in_ch[3:0]] : 1'b0);
    assign win_1b[1] = (pad_bottom)              ? 1'b0 : (in_ch < 16 ? w21[in_ch[3:0]] : 1'b0);
    assign win_1b[0] = (pad_bottom || pad_right) ? 1'b0 : (in_ch < 16 ? w22[in_ch[3:0]] : 1'b0);
    assign window_out = {7'd0, win_1b};
endmodule