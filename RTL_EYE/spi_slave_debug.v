`timescale 1ns / 1ps

module spi_slave_debug #(
    parameter TOTAL_BYTES = 7'd72 
)(
    input  wire clk,        // Xung nhịp hệ thống của FPGA (VD: 50MHz)
    input  wire rst_n,      // Nút nhấn Reset (Active Low)
    
    // Giao tiếp SPI từ MCU
    input  wire spi_cs,     // Chân Chip Select (Nối với P1.8 của MCU)
    input  wire spi_clk,    // Chân SPI Clock
    input  wire spi_mosi,   // Chân MOSI nhận dữ liệu
    
    // Output Debug
    output wire led_done    // Nối ra 1 con LED trên board FPGA
);

    // =========================================================================
    // 1. MẠCH ĐỒNG BỘ CDC (Chống nhiễu Clock Domain Crossing)
    // =========================================================================
    reg [2:0] cs_sync;
    reg [2:0] sck_sync;
    reg [1:0] mosi_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cs_sync   <= 3'b111;
            sck_sync  <= 3'b000;
            mosi_sync <= 2'b00;
        end else begin
            // Dịch tín hiệu qua các thanh ghi để đồng bộ với Clock của FPGA
            cs_sync   <= {cs_sync[1:0], spi_cs};
            sck_sync  <= {sck_sync[1:0], spi_clk};
            mosi_sync <= {mosi_sync[0], spi_mosi};
        end
    end

    // Phát hiện các sườn tín hiệu
    wire cs_active  = ~cs_sync[1];             // Đang trong quá trình truyền (CS = 0)
    wire cs_fall    = (cs_sync[2:1] == 2'b10); // Sườn âm CS -> Bắt đầu 1 khung mới
    wire cs_rise    = (cs_sync[2:1] == 2'b01); // Sườn dương CS -> Kết thúc truyền
    wire sck_rise   = (sck_sync[2:1] == 2'b01); // Sườn dương SCK (Dành cho SPI Mode 0)

    // =========================================================================
    // 2. BỘ ĐẾM BIT & BYTE
    // =========================================================================
    reg [2:0] bit_cnt;  // Đếm từ 0 đến 7 (8 bits)
    reg [6:0] byte_cnt; // Đếm số lượng byte nhận được
    reg       led_reg;  // Thanh ghi giữ trạng thái LED

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt  <= 3'd0;
            byte_cnt <= 7'd0;
            led_reg  <= 1'b0;
        end else begin
            
            // a. Khi MCU kéo CS xuống để bắt đầu gửi
            if (cs_fall) begin
                bit_cnt  <= 3'd0;
                byte_cnt <= 7'd0;
                led_reg  <= 1'b0; // Tắt đèn LED để chuẩn bị cho lượt test mới
            end 
            
            // b. Đang trong quá trình nhận dữ liệu
            else if (cs_active) begin
                if (sck_rise) begin
                    bit_cnt <= bit_cnt + 1'b1;
                    
                    // Nếu đếm đủ 8 bit -> Tăng biến đếm byte lên 1
                    if (bit_cnt == 3'd7) begin
                        byte_cnt <= byte_cnt + 1'b1;
                    end
                end
            end
            
            // c. Khi MCU kéo CS lên để kết thúc khung truyền
            else if (cs_rise) begin
                // CHỈ BẬT ĐÈN NẾU NHẬN ĐÚNG 72 BYTES
                if (byte_cnt == 7'd72) begin
                    led_reg <= 1'b1;
                end
            end
            
        end
    end

    // Xuất tín hiệu ra chân vật lý
    assign led_done = led_reg;

endmodule

