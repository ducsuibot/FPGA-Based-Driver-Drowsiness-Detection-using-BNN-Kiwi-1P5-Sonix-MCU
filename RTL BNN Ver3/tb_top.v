// TEST CONV1

// `timescale 1ns / 1ps

// module tb_top();

//     // ==========================================
//     // 1. KHAI BÁO TÍN HIỆU GIAO TIẾP VỚI TOP
//     // ==========================================
//     reg  clk;
//     reg  rst_n;
    
//     // Đóng vai STM32 gửi SPI
//     reg  spi_img_clk;
//     reg  spi_img_cs;
//     reg  spi_img_mosi;
    
//     // Tín hiệu xuất từ Top
//     wire result;
//     wire done;

//     // ==========================================
//     // 2. KHỞI TẠO MODULE TOP (DUT)
//     // ==========================================
//     top uut (
//         .clk(clk),
//         .rst_n(rst_n),
//         .spi_img_clk(spi_img_clk),
//         .spi_img_cs(spi_img_cs),
//         .spi_img_mosi(spi_img_mosi),
//         .result(result),
//         .done(done)
//     );

//     // ==========================================
//     // 3. TẠO XUNG CLOCK (100MHz)
//     // ==========================================
//     initial begin
//         clk = 0;
//         forever #5 clk = ~clk; 
//     end

//     // ==========================================
//     // 4. XỬ LÝ ẢNH TEXT VÀ GOLDEN MEMORY
//     // ==========================================
//     reg [23:0] img_txt [0:23];       
//     reg [7:0]  spi_tx_buffer [0:71]; 
    
//     // Mảng chứa Golden Output của lớp CONV1 (24x24 = 576 pixel)
//     reg [15:0] golden_mem [0:575]; 
    
//     integer r, c, p_idx;
//     initial begin
//         $readmemb("input_image.txt", img_txt);
//         $readmemh("golden_output_l1.txt", golden_mem); // Nạp file Golden CONV1
        
//         // VÒNG LẶP NÉN ẢNH CHUẨN CỦA BÁC
//         for (r = 0; r < 24; r = r + 1) begin
//             for (c = 0; c < 24; c = c + 1) begin
//                 p_idx = r * 24 + c;
//                 spi_tx_buffer[p_idx / 8][7 - (p_idx % 8)] = img_txt[r][23 - c];
//             end
//         end
//     end

//     // ==========================================
//     // 5. TASK MÔ PHỎNG GIAO THỨC SPI
//     // ==========================================
//     task send_spi_byte(input [7:0] data);
//         integer bit_idx;
//         begin
//             for (bit_idx = 7; bit_idx >= 0; bit_idx = bit_idx - 1) begin
//                 spi_img_mosi = data[bit_idx];
//                 #20 spi_img_clk = 1;
//                 #20 spi_img_clk = 0;
//             end
//         end
//     endtask

//     // =========================================================================
//     // 6. MODULE SNOOPING: ĐÓN LÕNG KẾT QUẢ CONV 1 TỪ BÊN TRONG TOP LEVEL
//     // =========================================================================
//     integer match_cnt = 0;
//     integer err_cnt = 0;
//     integer out_idx = 0;

//     always @(posedge clk) begin
//         // Đón lõng tín hiệu RAM Write nội bộ của mạch Top
//         // CONV1 ghi từ địa chỉ 72 đến 647 (576 pixel)
//         if (uut.act_we && (uut.act_wr_addr >= 72) && (uut.act_wr_addr < 648)) begin
//             out_idx = uut.act_wr_addr - 72;
            
//             // In log để theo dõi tiến độ
//             $display("Checking Pixel %0d | Addr: %0d | Data: %04X", out_idx, uut.act_wr_addr, uut.act_wr_data);
            
//             // So sánh với Golden
//             if (uut.act_wr_data === golden_mem[out_idx]) begin
//                 match_cnt = match_cnt + 1;
//             end else begin
//                 err_cnt = err_cnt + 1;
//                 $display("[FAIL] CONV1 Pixel %0d | FPGA: %04X | Golden: %04X", out_idx, uut.act_wr_data, golden_mem[out_idx]);
//             end

//             // Ngắt Testbench ngay khi CONV1 tính xong 576 pixel
//             if (out_idx >= 575) begin
//                 #10;
//                 $display("\n========================================");
//                 $display("       KET QUA TEST CONV 1 (TOP LEVEL)  ");
//                 $display("========================================");
//                 $display("Tong so Pixel da so sanh: 576");
//                 $display("So luong MATCH (Khop)   : %0d", match_cnt);
//                 $display("So luong LOI            : %0d", err_cnt);
//                 if (err_cnt == 0) begin
//                     $display(">>> TUYET VOI! CONV1 CHAY CHUAN XAC TREN TOP LEVEL! <<<");
//                 end else begin
//                     $display(">>> THAT BAI! CONV1 TREN TOP CO VAN DE <<<");
//                 end
//                 $display("========================================\n");
//                 $finish;
//             end
//         end
//     end

//     // ==========================================
//     // 7. KỊCH BẢN CHÍNH (MAIN TEST)
//     // ==========================================
//     integer i_byte;
//     initial begin
//         rst_n = 0;
//         spi_img_clk = 0;
//         spi_img_cs = 1;
//         spi_img_mosi = 0;

//         #100 rst_n = 1;
//         #200;

//         $display("==================================================");
//         $display("    BAT DAU CHAY MO PHONG TOAN MANG (TOP LEVEL)   ");
//         $display("==================================================");

//         $display("\n[STM32] Dang gui anh (72 bytes) qua SPI...");
//         spi_img_cs = 0; 
//         #40;
//         for (i_byte = 0; i_byte < 72; i_byte = i_byte + 1) begin
//             send_spi_byte(spi_tx_buffer[i_byte]);
//             #40; 
//         end
//         spi_img_cs = 1;
//         $display("[STM32] Da gui xong! FPGA dang thuc hien suy luan toan mang...");
//         $display("Hien dang theo doi doc lap vung nho cua lop CONV1...\n");
        
//         // Timeout bảo vệ
//         #5000000; 
//         $display("\n[LOI] Timeout! Mach bi treo o dau do.");
//         $stop;
//     end

// endmodule


// TEST CONV2

// `timescale 1ns / 1ps

// module tb_top();

//     // ==========================================
//     // 1. KHAI BÁO TÍN HIỆU GIAO TIẾP VỚI TOP
//     // ==========================================
//     reg  clk;
//     reg  rst_n;
    
//     // Đóng vai STM32 gửi SPI
//     reg  spi_img_clk;
//     reg  spi_img_cs;
//     reg  spi_img_mosi;
    
//     // Tín hiệu xuất từ Top
//     wire result;
//     wire done;

//     // ==========================================
//     // 2. KHỞI TẠO MODULE TOP (DUT)
//     // ==========================================
//     top uut (
//         .clk(clk),
//         .rst_n(rst_n),
//         .spi_img_clk(spi_img_clk),
//         .spi_img_cs(spi_img_cs),
//         .spi_img_mosi(spi_img_mosi),
//         .result(result),
//         .done(done)
//     );

//     // ==========================================
//     // 3. TẠO XUNG CLOCK (100MHz)
//     // ==========================================
//     initial begin
//         clk = 0;
//         forever #5 clk = ~clk; 
//     end

//     // ==========================================
//     // 4. XỬ LÝ ẢNH TEXT VÀ GOLDEN MEMORY (CONV2)
//     // ==========================================
//     reg [23:0] img_txt [0:23];       
//     reg [7:0]  spi_tx_buffer [0:71]; 
    
//     // Mảng chứa Golden Output của lớp CONV2 (12x12 = 144 pixel)
//     reg [15:0] golden_mem [0:143]; 
    
//     integer r, c, p_idx;
//     initial begin
//         $readmemb("input_image.txt", img_txt);
//         // NẠP FILE GOLDEN CỦA LỚP CONV2
//         $readmemh("golden_output_l2.txt", golden_mem); 
        
//         for (r = 0; r < 24; r = r + 1) begin
//             for (c = 0; c < 24; c = c + 1) begin
//                 p_idx = r * 24 + c;
//                 spi_tx_buffer[p_idx / 8][7 - (p_idx % 8)] = img_txt[r][23 - c];
//             end
//         end
//     end

//     // ==========================================
//     // 5. TASK MÔ PHỎNG SPI
//     // ==========================================
//     task send_spi_byte(input [7:0] data);
//         integer bit_idx;
//         begin
//             for (bit_idx = 7; bit_idx >= 0; bit_idx = bit_idx - 1) begin
//                 spi_img_mosi = data[bit_idx];
//                 #20 spi_img_clk = 1;
//                 #20 spi_img_clk = 0;
//             end
//         end
//     endtask

//     // =========================================================================
//     // 6. MODULE SNOOPING: ĐÓN LÕNG KẾT QUẢ CONV 2 TỪ BÊN TRONG TOP LEVEL
//     // =========================================================================
//     integer match_cnt = 0;
//     integer err_cnt = 0;
//     integer out_idx = 0;

//     always @(posedge clk) begin
//         // Đón lõng tín hiệu RAM Write của mạch Top
//         // CONV2 ghi từ địa chỉ 792 đến 935 (144 pixel)
//         if (uut.act_we && (uut.act_wr_addr >= 792) && (uut.act_wr_addr < 936)) begin
//             out_idx = uut.act_wr_addr - 792;
            
//             // So sánh với Golden
//             if (uut.act_wr_data === golden_mem[out_idx]) begin
//                 match_cnt = match_cnt + 1;
//             end else begin
//                 err_cnt = err_cnt + 1;
//                 $display("[FAIL] CONV2 Pixel %0d | Addr: %0d | FPGA: %04X | Golden: %04X", 
//                           out_idx, uut.act_wr_addr, uut.act_wr_data, golden_mem[out_idx]);
//             end

//             // Ngắt ngay khi CONV2 tính xong 144 pixel
//             if (out_idx >= 143) begin
//                 #10;
//                 $display("\n========================================");
//                 $display("       KET QUA TEST CONV 2 (TOP LEVEL)  ");
//                 $display("========================================");
//                 $display("Tong so Pixel da so sanh: 144");
//                 $display("So luong MATCH (Khop)   : %0d", match_cnt);
//                 $display("So luong LOI            : %0d", err_cnt);
//                 if (err_cnt == 0) begin
//                     $display(">>> TUYET VOI! CONV2 CHAY CHUAN XAC TREN TOP LEVEL! <<<");
//                 end else begin
//                     $display(">>> THAT BAI! Kiem tra lai FSM CONV2 hoac Dual-Threshold. <<<");
//                 end
//                 $display("========================================\n");
//                 $finish;
//             end
//         end
//     end

//     // ==========================================
//     // 7. KỊCH BẢN CHÍNH (MAIN TEST)
//     // ==========================================
//     integer i_byte;
//     initial begin
//         rst_n = 0;
//         spi_img_clk = 0;
//         spi_img_cs = 1;
//         spi_img_mosi = 0;

//         #100 rst_n = 1;
//         #200;

//         $display("==================================================");
//         $display("    BAT DAU CHAY MO PHONG TOAN MANG (TOP LEVEL)   ");
//         $display("==================================================");

//         $display("\n[STM32] Dang gui anh (72 bytes) qua SPI...");
//         spi_img_cs = 0; 
//         #40;
//         for (i_byte = 0; i_byte < 72; i_byte = i_byte + 1) begin
//             send_spi_byte(spi_tx_buffer[i_byte]);
//             #40; 
//         end
//         spi_img_cs = 1;
//         $display("[STM32] Da gui xong! FPGA dang thuc hien suy luan...");
//         $display("Hien dang theo doi vung nho cua lop CONV2 (792-935)...");
//         $display("Canh bao: CONV2 tinh rat lau, vui long kien nhan...\n");
        
//         // Timeout bảo vệ (Tăng lên vì CONV2 chạy lâu)
//         #50000000; 
//         $display("\n[LOI] Timeout! Mach bi treo.");
//         $stop;
//     end

// endmodule


// TEST FC1


// `timescale 1ns / 1ps

// module tb_top();

//     // ==========================================
//     // 1. KHAI BÁO TÍN HIỆU GIAO TIẾP VỚI TOP
//     // ==========================================
//     reg  clk;
//     reg  rst_n;
    
//     // Đóng vai STM32 gửi SPI
//     reg  spi_img_clk;
//     reg  spi_img_cs;
//     reg  spi_img_mosi;
    
//     // Tín hiệu xuất từ Top
//     wire result;
//     wire done;

//     // ==========================================
//     // 2. KHỞI TẠO MODULE TOP (DUT)
//     // ==========================================
//     top uut (
//         .clk(clk),
//         .rst_n(rst_n),
//         .spi_img_clk(spi_img_clk),
//         .spi_img_cs(spi_img_cs),
//         .spi_img_mosi(spi_img_mosi),
//         .result(result),
//         .done(done)
//     );

//     // ==========================================
//     // 3. TẠO XUNG CLOCK (100MHz)
//     // ==========================================
//     initial begin
//         clk = 0;
//         forever #5 clk = ~clk; 
//     end

//     // ==========================================
//     // 4. XỬ LÝ ẢNH TEXT VÀ GOLDEN MEMORY (FC1)
//     // ==========================================
//     reg [23:0] img_txt [0:23];       
//     reg [7:0]  spi_tx_buffer [0:71]; 
    
//     // Mảng chứa Golden Output của lớp FC1 (Đã nén thành 4 Word 16-bit)
//     reg [15:0] golden_mem [0:3]; 
    
//     integer r, c, p_idx;
//     initial begin
//         $readmemb("input_image.txt", img_txt);
//         // NẠP FILE GOLDEN CỦA LỚP FC1 (Chứa 4 Word ghi vào RAM)
//         $readmemh("golden_output_fc1.txt", golden_mem); 
        
//         for (r = 0; r < 24; r = r + 1) begin
//             for (c = 0; c < 24; c = c + 1) begin
//                 p_idx = r * 24 + c;
//                 spi_tx_buffer[p_idx / 8][7 - (p_idx % 8)] = img_txt[r][23 - c];
//             end
//         end
//     end

//     // ==========================================
//     // 5. TASK MÔ PHỎNG SPI
//     // ==========================================
//     task send_spi_byte(input [7:0] data);
//         integer bit_idx;
//         begin
//             for (bit_idx = 7; bit_idx >= 0; bit_idx = bit_idx - 1) begin
//                 spi_img_mosi = data[bit_idx];
//                 #20 spi_img_clk = 1;
//                 #20 spi_img_clk = 0;
//             end
//         end
//     endtask

//     // =========================================================================
//     // 6. MODULE SNOOPING: ĐÓN LÕNG KẾT QUẢ FC 1 TỪ BÊN TRONG TOP LEVEL
//     // =========================================================================
//     integer match_cnt = 0;
//     integer err_cnt = 0;
//     integer out_idx = 0;

//     always @(posedge clk) begin
//         // Đón lõng tín hiệu RAM Write nội bộ của mạch Top
//         // FC1 ghi 4 Word vào địa chỉ 972 đến 975
//         if (uut.act_we && (uut.act_wr_addr >= 972) && (uut.act_wr_addr < 976)) begin
//             out_idx = uut.act_wr_addr - 972;
            
//             // So sánh với Golden (Dùng === để khớp chính xác X/Z)
//             if (uut.act_wr_data === golden_mem[out_idx]) begin
//                 match_cnt = match_cnt + 1;
//                 $display("[MATCH] FC1 Chunk %0d | Addr: %0d | Data: %04X", out_idx, uut.act_wr_addr, uut.act_wr_data);
//             end else begin
//                 err_cnt = err_cnt + 1;
//                 $display("[FAIL] FC1 Chunk %0d | Addr: %0d | FPGA: %04X | Golden: %04X", 
//                           out_idx, uut.act_wr_addr, uut.act_wr_data, golden_mem[out_idx]);
//             end

//             // Ngắt ngay khi FC1 ghi xong 4 Word
//             if (out_idx >= 3) begin
//                 #10;
//                 $display("\n========================================");
//                 $display("       KET QUA TEST FC 1 (TOP LEVEL)    ");
//                 $display("========================================");
//                 $display("Tong so Word da so sanh: 4 (64 Nơ-ron)");
//                 $display("So luong MATCH (Khop)  : %0d", match_cnt);
//                 $display("So luong LOI           : %0d", err_cnt);
//                 if (err_cnt == 0) begin
//                     $display(">>> TUYET VOI! FC1 CHAY CHUAN XAC TREN TOP LEVEL! <<<");
//                 end else begin
//                     $display(">>> THAT BAI! Kiem tra lại logic Pre-fetch FC1. <<<");
//                 end
//                 $display("========================================\n");
//                 $finish;
//             end
//         end
//     end

//     // ==========================================
//     // 7. KỊCH BẢN CHÍNH (MAIN TEST)
//     // ==========================================
//     integer i_byte;
//     initial begin
//         rst_n = 0;
//         spi_img_clk = 0;
//         spi_img_cs = 1;
//         spi_img_mosi = 0;

//         #100 rst_n = 1;
//         #200;

//         $display("==================================================");
//         $display("    BAT DAU CHAY MO PHONG TOAN MANG (TOP LEVEL)   ");
//         $display("==================================================");

//         $display("\n[STM32] Dang gui anh (72 bytes) qua SPI...");
//         spi_img_cs = 0; 
//         #40;
//         for (i_byte = 0; i_byte < 72; i_byte = i_byte + 1) begin
//             send_spi_byte(spi_tx_buffer[i_byte]);
//             #40; 
//         end
//         spi_img_cs = 1;
//         $display("[STM32] Da gui xong! FPGA dang thuc hien suy luan...");
//         $display("Hien dang theo doi lop FC1 (972-975)...");
        
//         // Timeout bảo vệ (Tăng cao vì phải chờ CONV2 chạy xong)
//         #100000000; 
//         $display("\n[LOI] Timeout! Mach bi treo.");
//         $stop;
//     end

// endmodule


// TEST OUTPUT

// `timescale 1ns / 1ps

// module tb_top();

//     // ==========================================
//     // 1. KHAI BÁO TÍN HIỆU
//     // ==========================================
//     reg  clk, rst_n;
//     reg  spi_img_clk, spi_img_cs, spi_img_mosi;
//     wire result, done;

//     integer r, c, p_idx, i_byte, b_idx;
//     reg [23:0] img_txt [0:23];       
//     reg [7:0]  spi_tx_buffer [0:71]; 

//     // ==========================================
//     // 2. KHỞI TẠO DUT
//     // ==========================================
//     top uut (
//         .clk(clk), .rst_n(rst_n),
//         .spi_img_clk(spi_img_clk), .spi_img_cs(spi_img_cs), .spi_img_mosi(spi_img_mosi),
//         .result(result), .done(done)
//     );

//     initial begin clk = 0; forever #5 clk = ~clk; end

//     // =========================================================================
//     // 3. LOGIC IN BÁO CÁO (CHỈ HIỆN LAYER 3 VÀ LAYER 4) - BẢN 32 NODE
//     // =========================================================================
    
//     integer fc_pulse_cnt = 0;

//     always @(negedge clk) begin
//         // Chỉ bắt xung valid_out khi FSM đang ở trạng thái FC (FC1 hoặc FC2)
//         if (uut.u_fsm.is_fc && uut.u_datapath.valid_out) begin
            
//             // --- LAYER 3: FC1 (Từ Node 0 đến Node 31) ---
//             if (fc_pulse_cnt < 32) begin
//                 if (fc_pulse_cnt == 0)
//                     $display("\n# >>> LAYER 3: FULLY CONNECTED 1 (Toan bo 32 Node) <<<");

//                 $display("# Node [%0d] | Popcount: %0d/576 | Threshold: %0d -> Bit Out: %b",
//                          fc_pulse_cnt, uut.u_datapath.acc_reg,
//                          uut.u_datapath.thresh_reg[14:0], uut.u_datapath.out_bit);

//                 fc_pulse_cnt = fc_pulse_cnt + 1;
//             end
            
//             // --- LAYER 4: FC2 (Node chốt hạ cuối cùng) ---
//             else if (fc_pulse_cnt == 32) begin
//                 $display("\n# >>> LAYER 4: FULLY CONNECTED 2 (Lop chot ha) <<<");
//                 // Popcount của FC2 bây giờ chỉ xét trên 32 node
//                 $display("# FINAL DECISION | Popcount: %0d/32 | Threshold: %0d -> RESULT: %b\n#",
//                          uut.u_datapath.acc_reg,
//                          uut.u_datapath.thresh_reg[14:0], uut.u_datapath.out_bit);

//                 fc_pulse_cnt = fc_pulse_cnt + 1;
//             end
            
//         end
//     end

//     // ==========================================
//     // 4. KỊCH BẢN CHẠY CHÍNH (STIMULUS)
//     // ==========================================
//     initial begin
//         $display("# ==================================================");
//         $display("#  BAO CAO TINH TOAN BIT-BY-BIT TREN FPGA (MOI NHAT)");
//         $display("# ==================================================\n#");
//         $display("# Sonix: Bat dau gui anh (72 bytes) qua SPI...");
        
//         // Đọc file ảnh
//         $readmemb("input_image.txt", img_txt);
//         for (r = 0; r < 24; r = r + 1) begin
//             for (c = 0; c < 24; c = c + 1) begin
//                 p_idx = r * 24 + c;
//                 spi_tx_buffer[p_idx / 8][7 - (p_idx % 8)] = img_txt[r][23 - c];
//             end
//         end

//         // Khởi tạo
//         rst_n = 0; spi_img_clk = 0; spi_img_cs = 1; spi_img_mosi = 0;
//         #100 rst_n = 1;

//         // Gửi SPI
//         spi_img_cs = 0;
//         for (i_byte = 0; i_byte < 72; i_byte = i_byte + 1) begin
//             for (b_idx = 7; b_idx >= 0; b_idx = b_idx - 1) begin
//                 spi_img_mosi = spi_tx_buffer[i_byte][b_idx];
//                 #20 spi_img_clk = 1; #20 spi_img_clk = 0;
//             end
//         end
//         spi_img_cs = 1;
//         $display("# sonix: Da gui xong! He thong FPGA bat dau xu ly mang AI...");

//         // Đợi FPGA tính toán xong và in kết luận
//         wait(done);
//         #100;
//         $finish;
//     end

// endmodule

`timescale 1ns / 1ps

module tb_top();

    // ==========================================
    // 1. KHAI BÁO TÍN HIỆU
    // ==========================================
    reg  clk, rst_n;
    reg  spi_img_clk, spi_img_cs, spi_img_mosi;
    wire spi_miso; 
    wire result, done;

    integer r, c, p_idx, i_byte, b_idx;
    reg [23:0] img_txt [0:23];       
    reg [7:0]  spi_tx_buffer [0:71]; 

    // ==========================================
    // 2. KHỞI TẠO DUT (Mẫu thử)
    // ==========================================
    top uut (
        .clk(clk), 
        .rst_n(rst_n),
        .spi_img_clk(spi_img_clk), 
        .spi_img_cs(spi_img_cs), 
        .spi_img_mosi(spi_img_mosi),
        .spi_miso(spi_miso), 
        .result(result), 
        .done(done)
    );

    // Tạo xung Clock hệ thống 100MHz (10ns)
    initial begin 
        clk = 0; 
        forever #5 clk = ~clk; 
    end

    // Xuất file sóng Waveform
    initial begin
        $dumpfile("tb_top_waveform.vcd"); 
        $dumpvars(0, tb_top);             
    end

    // =========================================================================
    // 3. LOGIC MONITOR (Theo dõi và in báo cáo)
    // =========================================================================
    integer fc_pulse_cnt = 0;

    always @(posedge clk) begin
        if (uut.u_fsm.is_fc && uut.u_datapath.valid_out) begin
            if (fc_pulse_cnt < 32) begin
                if (fc_pulse_cnt == 0)
                    $display("\n# >>> LAYER 3: FULLY CONNECTED 1 (32 Nodes) <<<");

                $display("# Node [%0d] | Popcount: %0d/576 | Threshold: %0d -> Bit Out: %b",
                         fc_pulse_cnt, uut.u_datapath.acc_reg,
                         uut.u_datapath.thresh_reg[14:0], uut.u_datapath.out_bit);

                fc_pulse_cnt = fc_pulse_cnt + 1;
            end
            else if (fc_pulse_cnt == 32) begin
                $display("\n# >>> LAYER 4: FULLY CONNECTED 2 (Output Layer) <<<");
                $display("# FINAL DECISION | Popcount: %0d/32 | Threshold: %0d -> RESULT: %b\n#",
                         uut.u_datapath.acc_reg,
                         uut.u_datapath.thresh_reg[14:0], uut.u_datapath.out_bit);
                fc_pulse_cnt = fc_pulse_cnt + 1;
            end
        end
    end

    // ==========================================
    // 4. KỊCH BẢN MÔ PHỎNG (Stimulus)
    // ==========================================
    initial begin
        $display("# ==================================================");
        $display("#  HE THONG AI FPGA - KRAI TESTBENCH LOGIC");
        $display("# ==================================================\n#");
        
        $readmemb("input_image.txt", img_txt);
        for (r = 0; r < 24; r = r + 1) begin
            for (c = 0; c < 24; c = c + 1) begin
                p_idx = r * 24 + c;
                spi_tx_buffer[p_idx / 8][7 - (p_idx % 8)] = img_txt[r][23 - c];
            end
        end

        rst_n = 0; spi_img_clk = 0; spi_img_cs = 1; spi_img_mosi = 0;
        #100 rst_n = 1; 

        #50;
        $display("# Sonix: Dang gui 72 bytes anh qua SPI...");
        
        // --- QUÁ TRÌNH STM32 GỬI ẢNH (MOSI) ---
        spi_img_cs = 0; 
        for (i_byte = 0; i_byte < 72; i_byte = i_byte + 1) begin
            for (b_idx = 7; b_idx >= 0; b_idx = b_idx - 1) begin
                spi_img_mosi = spi_tx_buffer[i_byte][b_idx];
                #20 spi_img_clk = 1; 
                #20 spi_img_clk = 0;
            end
        end
        #20 spi_img_cs = 1; 
        $display("# Sonix: Da gui xong! FPGA dang xu ly...");

        // --- CHỜ FPGA TÍNH TOÁN XONG ---
        wait(done == 1); 
        
        // Đợi FPGA chuyển hẳn về IDLE để cờ Busy tụt xuống 0
        #150; 
        
        // --- QUÁ TRÌNH STM32 ĐỌC KẾT QUẢ (MISO) ---
        $display("# Sonix: FPGA da xong! Dang doc byte trang thai qua SPI MISO...");
        spi_img_cs = 0; // STM32 kéo CS xuống 0
        #40; // Đợi ổn định một chút
        
        // STM32 cấp 8 nhịp Clock để lôi 8 bit từ MISO ra
        for (b_idx = 7; b_idx >= 0; b_idx = b_idx - 1) begin
            spi_img_clk = 1; #20; // Sườn dương (STM32 lấy mẫu)
            spi_img_clk = 0; #20; // Sườn âm (FPGA dịch bit ra MISO)
        end
        
        #20 spi_img_cs = 1; // STM32 kéo CS lên 1 để kết thúc đọc
        
        // Đợi thêm một chút để lưu Waveform đẹp
        #200; 
        
        $display("# ==================================================");
        $display("# KET LUAN CUOI CUNG TU PHAN CUNG FPGA:");
        $display("# Popcount FC2: %0d/32", uut.u_fsm.fc2_pop);
        
        if (result == 1)
            $display("# Ket qua tren chan Result: 1 (MO MAT)");
        else
            $display("# Ket qua tren chan Result: 0 (NHAM MAT)");
            
        $display("# ==================================================");
        $display("# Mo phong ket thuc!");
        #100;
        $finish;
    end

endmodule