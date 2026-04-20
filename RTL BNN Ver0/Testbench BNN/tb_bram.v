`timescale 1ns / 1ps

module tb_bram();

    // ==========================================
    // 1. TÍN HIỆU KẾT NỐI
    // ==========================================
    reg clk;
    reg rst_n;
    
    // Tín hiệu SPI từ "STM32 Ảo"
    reg spi_clk;
    reg spi_cs;
    reg spi_mosi;
    
    // Tín hiệu nội bộ nối giữa SPI Slave và BRAM
    wire       rx_valid;
    wire [7:0] rx_data;
    wire [6:0] rx_addr;
    wire       frame_done;

    // Các tín hiệu không dùng tới của padding_and_buffer (nối đất)
    wire [15:0] rd_data;
    wire [15:0] window_out;
    wire [15:0] center_pixel;

    // ==========================================
    // 2. KHỞI TẠO MODULE SPI SLAVE
    // ==========================================
    spi_slave #(
        .TOTAL_BYTES(7'd72)
    ) u_spi (
        .clk(clk),
        .rst_n(rst_n),
        .spi_clk(spi_clk),
        .spi_cs(spi_cs),
        .spi_mosi(spi_mosi),
        .rx_valid(rx_valid),
        .rx_data(rx_data),
        .rx_addr(rx_addr),
        .frame_done(frame_done)
    );

    // ==========================================
    // 3. KHỞI TẠO MODULE PADDING & BUFFER (BRAM)
    // ==========================================
    padding_and_buffer u_pad (
        .clk(clk),
        .rst_n(rst_n),
        .spi_we(rx_valid),        // Nối trực tiếp cờ valid thành cờ Write Enable
        .spi_addr(rx_addr),       // Nối địa chỉ (0-71)
        .spi_data(rx_data),       // Nối dữ liệu (8-bit)
        
        // Các tín hiệu điều khiển mạng AI (Tạm thời tắt đi vì chỉ test nạp ảnh)
        .rd_addr(11'd0), .wr_en(1'b0), .wr_addr(11'd0), .wr_data(16'd0),
        .shift_en(1'b0), .is_conv2(1'b0), .is_img_read(1'b0),
        .pad_x(5'd0), .pad_y(5'd0), .in_ch(5'd0),
        
        .rd_data(rd_data),
        .window_out(window_out),
        .center_pixel(center_pixel)
    );

    // ==========================================
    // 4. TẠO CLOCK HỆ THỐNG (50MHz)
    // ==========================================
    initial begin
        clk = 0;
        forever #10 clk = ~clk; // Chu kỳ 20ns
    end

    // ==========================================
    // 5. ĐỌC FILE ẢNH & ĐÓNG GÓI 72 BYTES
    // ==========================================
    reg [23:0] img_txt [0:23];       // Đọc 24 dòng, 24 bit/dòng
    reg [7:0]  spi_tx_buffer [0:71]; // Đóng gói thành 72 byte
    
    integer r, c, byte_ptr, bit_ptr;
    reg [7:0] current_byte;

    initial begin
        // Đảm bảo file input_image.txt nằm cùng thư mục mô phỏng
        $readmemb("input_image.txt", img_txt);
        
        byte_ptr = 0; bit_ptr = 7; current_byte = 8'd0;
        
        // Thuật toán quét Trái->Phải, Trên->Xuống và đóng gói MSB-First
        for (r = 0; r < 24; r = r + 1) begin
            for (c = 23; c >= 0; c = c - 1) begin // Mảng Verilog [23:0] thì 23 là bit trái cùng
                current_byte[bit_ptr] = img_txt[r][c];
                if (bit_ptr == 0) begin
                    spi_tx_buffer[byte_ptr] = current_byte;
                    byte_ptr = byte_ptr + 1;
                    bit_ptr = 7;
                end else begin
                    bit_ptr = bit_ptr - 1;
                end
            end
        end
    end

    // ==========================================
    // 6. TASK GIẢ LẬP GIAO THỨC SPI
    // ==========================================
    task send_spi_byte(input [7:0] data);
        integer b;
        begin
            for (b = 7; b >= 0; b = b - 1) begin
                spi_mosi = data[b];     // Đẩy bit ra MOSI (MSB First)
                #40 spi_clk = 1;        // Kéo Clock lên (Tốc độ SPI chậm hơn Clock hệ thống)
                #40 spi_clk = 0;        // Kéo Clock xuống
            end
        end
    endtask

    // ==========================================
    // 7. KỊCH BẢN CHÍNH (MAIN TEST)
    // ==========================================
    integer i;
    initial begin
        // Khởi tạo trạng thái ban đầu
        rst_n = 0;
        spi_clk = 0;
        spi_cs = 1;
        spi_mosi = 0;

        #100 rst_n = 1;
        #100;

        $display("\n==================================================");
        $display(" BAT DAU TRUYEN ANH QUA SPI (72 BYTES)");
        $display("==================================================");

        // Kéo CS xuống để bắt đầu truyền
        spi_cs = 0; 
        #100;
        
        // Truyền 72 byte
        for (i = 0; i < 72; i = i + 1) begin
            send_spi_byte(spi_tx_buffer[i]);
            // Tạo khoảng trễ nhỏ giữa các byte (giống vi điều khiển thực tế)
            #100; 
        end
        
        // Kéo CS lên để kết thúc truyền
        spi_cs = 1;
        $display("=> STM32 da truyen xong! Cho co frame_done tu FPGA...\n");

        // Đợi module spi_slave báo nhận xong
        wait(frame_done == 1'b1);
        #50;

        $display("==================================================");
        $display(" DA NHAN CO FRAME_DONE! KIEM TRA NOI DUNG BRAM");
        $display("==================================================");
        
        // Dùng đường dẫn phân cấp (Hierarchical Reference) chọc thẳng vào RAM để đọc
        for (i = 0; i < 72; i = i + 1) begin
            $display("BRAM_Addr [%2d] | Du lieu luu: %b (Hex: %2h) | Byte goc STM32: %b", 
                     i, u_pad.act_ram[i][7:0], u_pad.act_ram[i][7:0], spi_tx_buffer[i]);
                     
            if (u_pad.act_ram[i][7:0] !== spi_tx_buffer[i]) begin
                $display(">>> [LOI] Du lieu khong khop tai byte %d <<<", i);
            end
        end
        
        $display("\n==================================================");
        $display(" HOAN TAT TEST KIEM TRA BRAM!");
        $display("==================================================\n");

        $stop;
    end

endmodule