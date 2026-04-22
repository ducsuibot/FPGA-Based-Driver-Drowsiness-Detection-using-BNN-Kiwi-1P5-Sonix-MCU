`timescale 1ns / 1ps

module spi_slave #(
    // Kích thước ảnh: 24x24 pixel nhị phân (1-bit/pixel) = 576 bits = 72 bytes
    parameter TOTAL_BYTES = 7'd72 
)(
    input  wire       clk,          // Xung nhịp hệ thống FPGA (rất nhanh, ví dụ 50MHz)
    input  wire       rst_n,        // Reset tích cực mức thấp
    
    // Giao tiếp SPI từ MCU (Slave Mode)
    input  wire       spi_clk,      // Xung SPI từ MCU (chậm hơn clk hệ thống)
    input  wire       spi_cs,       // Chip Select từ MCU (Tích cực mức thấp)
    input  wire       spi_mosi,     // Đường truyền dữ liệu ảnh từ MCU
    
    // Giao tiếp với RAM Đệm nội bộ
    output reg        rx_valid,     // Cờ báo: Đã nhận đủ 1 Byte (8-bit)
    output reg  [7:0] rx_data,      // Dữ liệu 1 Byte vừa nhận
    output reg  [6:0] rx_addr,      // Địa chỉ ghi vào RAM (0 -> 71)
    
    // Tín hiệu trạng thái FSM
    output reg        frame_done    // Cờ báo: Đã nhận xong toàn bộ 1 khung ảnh
);

    // =========================================================================
    // 1. MẠCH ĐỒNG BỘ HÓA (CDC - CLOCK DOMAIN CROSSING)
    // Chuyển tín hiệu từ Clock MCU sang Clock FPGA để chống nhiễu Metastability
    // =========================================================================
    reg [2:0] spi_clk_sync;
    reg [2:0] spi_cs_sync;
    reg [1:0] mosi_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_clk_sync <= 3'b000;
            spi_cs_sync  <= 3'b111; // CS mặc định ở mức cao (Inactive)
            mosi_sync    <= 2'b00;
        end else begin
            // Dịch bit qua các Flip-Flop để đồng bộ hóa
            spi_clk_sync <= {spi_clk_sync[1:0], spi_clk};
            spi_cs_sync  <= {spi_cs_sync[1:0],  spi_cs};
            mosi_sync    <= {mosi_sync[0],      spi_mosi};
        end
    end

    // Phát hiện sườn (Edge Detection) dựa trên các tín hiệu đã đồng bộ
    wire spi_clk_rise  = (spi_clk_sync[2:1] == 2'b01); // Sườn dương SPI Clock
    wire spi_cs_fall   = (spi_cs_sync[2:1]  == 2'b10); // Sườn âm SPI CS (Bắt đầu)
    wire spi_cs_rise   = (spi_cs_sync[2:1]  == 2'b01); // Sườn dương SPI CS (Kết thúc)
    wire spi_cs_active = ~spi_cs_sync[1];              // Trạng thái CS đang thấp

    // =========================================================================
    // 2. LOGIC NHẬN DỮ LIỆU (SHIFT REGISTER & COUNTERS)
    // =========================================================================
    reg [2:0] bit_cnt;   // Đếm số bit trong 1 Byte (0 -> 7)
    reg [7:0] shift_reg; // Thanh ghi dịch

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt    <= 3'd0;
            shift_reg  <= 8'd0;
            rx_valid   <= 1'b0;
            rx_data    <= 8'd0;
            rx_addr    <= 7'd0;
            frame_done <= 1'b0;
        end else begin
            // Mặc định các xung điều khiển chỉ tồn tại trong 1 chu kỳ clk
            rx_valid   <= 1'b0;
            frame_done <= 1'b0;

            // KHI MCU KÉO CS XUỐNG BẮT ĐẦU GỬI ẢNH
            if (spi_cs_fall) begin
                bit_cnt <= 3'd0;
                rx_addr <= 7'd0;  // Reset địa chỉ RAM về 0 cho khung ảnh mới
            end
            
            // TRONG QUÁ TRÌNH MCU ĐANG GỬI DỮ LIỆU
            else if (spi_cs_active) begin
                if (rx_valid) begin
                    rx_addr <= rx_addr + 1'b1;
                end
                
                if (spi_clk_rise) begin
                    shift_reg <= {shift_reg[6:0], mosi_sync[1]};
                    bit_cnt   <= bit_cnt + 1'b1;
                    
                    if (bit_cnt == 3'd7) begin
                        rx_valid <= 1'b1;
                        rx_data  <= {shift_reg[6:0], mosi_sync[1]}; 
                    end
                end
            end
            
            // KHI MCU KÉO CS LÊN KẾT THÚC GỬI ẢNH (ĐÃ FIX LỖI LOGIC)
            else if (spi_cs_rise) begin
                // Gộp chung điều kiện: Đảm bảo bắt được khung hình nếu địa chỉ nhảy đến 71 hoặc 72
                // (Bù trừ độ trễ của các Flip-Flop đồng bộ)
                if (rx_addr >= TOTAL_BYTES - 1) begin 
                    frame_done <= 1'b1;
                end
            end
        end
    end

endmodule