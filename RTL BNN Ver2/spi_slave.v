module spi_slave #(
    parameter TOTAL_BYTES = 7'd72 
)(
    input  wire       clk,          
    input  wire       rst_n,        
    
    // Giao tiếp SPI từ MCU
    input  wire       spi_clk,      
    input  wire       spi_cs,       
    input  wire       spi_mosi,     
    output wire       spi_miso,     // <--- THÊM CHÂN MISO
    
    // Giao tiếp với RAM
    output reg        rx_valid,     
    output reg  [7:0] rx_data,      
    output reg  [6:0] rx_addr,      
    output reg        frame_done,

    // Giao tiếp với FSM
    input  wire       busy_in,      // <--- THÊM: Đọc cờ BUSY từ FSM
    input  wire       result_in     // <--- THÊM: Đọc cờ RESULT từ FSM
);

    // --- 1. MẠCH ĐỒNG BỘ CDC ---
    reg [2:0] spi_clk_sync;
    reg [2:0] spi_cs_sync;
    reg [1:0] mosi_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_clk_sync <= 3'b000;
            spi_cs_sync  <= 3'b111; 
            mosi_sync    <= 2'b00;
        end else begin
            spi_clk_sync <= {spi_clk_sync[1:0], spi_clk};
            spi_cs_sync  <= {spi_cs_sync[1:0],  spi_cs};
            mosi_sync    <= {mosi_sync[0],      spi_mosi};
        end
    end

    wire spi_clk_rise  = (spi_clk_sync[2:1] == 2'b01); // Sườn dương
    wire spi_clk_fall  = (spi_clk_sync[2:1] == 2'b10); // <--- THÊM: Sườn âm để dịch MISO
    wire spi_cs_fall   = (spi_cs_sync[2:1]  == 2'b10); 
    wire spi_cs_rise   = (spi_cs_sync[2:1]  == 2'b01); 
    wire spi_cs_active = ~spi_cs_sync[1]; 

    // --- 2. LOGIC MISO (TRUYỀN VỀ MCU) ---
    reg [7:0] tx_shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_shift_reg <= 8'd0;
        end else begin
            if (spi_cs_fall) begin
                // Ngay khi MCU kéo CS xuống, gói Trạng Thái vào thanh ghi
                // Byte = {BUSY, 0, 0, 0, 0, 0, 0, RESULT}
                tx_shift_reg <= {busy_in, 6'b000000, result_in};
            end else if (spi_cs_active && spi_clk_fall) begin
                // Dịch bit ra MISO ở sườn âm SPI Clock (Mode 0)
                tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
            end
        end
    end
    
    // Gắn trở kháng cao (High-Z) cho MISO khi không giao tiếp để bảo vệ chip
    assign spi_miso = spi_cs_active ? tx_shift_reg[7] : 1'bz;

    // --- 3. LOGIC MOSI (NHẬN TỪ MCU - CÓ KHÓA BẢO VỆ) ---
    reg [2:0] bit_cnt;
    reg [7:0] shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt    <= 3'd0;
            shift_reg  <= 8'd0;
            rx_valid   <= 1'b0;
            rx_data    <= 8'd0;
            rx_addr    <= 7'd0;
            frame_done <= 1'b0;
        end else begin
            rx_valid   <= 1'b0;
            frame_done <= 1'b0;

            if (spi_cs_fall) begin
                bit_cnt <= 3'd0;
                rx_addr <= 7'd0;  // Bất cứ khi nào CS rớt xuống, reset địa chỉ
            end
            
            // CHỈ NHẬN DỮ LIỆU KHI FPGA KHÔNG BẬN (!busy_in)
            else if (spi_cs_active && !busy_in) begin
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
            
            else if (spi_cs_rise) begin
                if (rx_addr >= TOTAL_BYTES - 1) begin 
                    frame_done <= 1'b1;
                end
            end
        end
    end
endmodule