`timescale 1ns / 1ps

module tb_top();

    // ==========================================
    // 1. KHAI BÁO TÍN HIỆU GIAO TIẾP VỚI TOP
    // ==========================================
    reg  clk;
    reg  rst_n;
    
    // Đóng vai STM32 gửi SPI
    reg  spi_img_clk;
    reg  spi_img_cs;
    reg  spi_img_mosi;
    
    // Tín hiệu xuất từ Top
    wire result;
    wire done;

    // ==========================================
    // 2. KHỞI TẠO MODULE TOP (DUT)
    // ==========================================
    top uut (
        .clk(clk),
        .rst_n(rst_n),
        .spi_img_clk(spi_img_clk),
        .spi_img_cs(spi_img_cs),
        .spi_img_mosi(spi_img_mosi),
        .result(result),
        .done(done)
    );

    // ==========================================
    // 3. TẠO XUNG CLOCK (100MHz)
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // ==========================================
    // 4. XỬ LÝ ẢNH TEXT 
    // ==========================================
    reg [23:0] img_txt [0:23];       
    reg [7:0]  spi_tx_buffer [0:71]; 
    
    // Kỳ vọng cho bức ảnh input_image.txt hiện tại là MỞ MẮT (1)
    reg expected_result = 1'b1; 
    
    integer r, c, p_idx;
    initial begin
        $readmemb("input_image.txt", img_txt);
        
        // VÒNG LẶP NÉN ẢNH CHUẨN CỦA BÁC
        for (r = 0; r < 24; r = r + 1) begin
            for (c = 0; c < 24; c = c + 1) begin
                p_idx = r * 24 + c;
                spi_tx_buffer[p_idx / 8][7 - (p_idx % 8)] = img_txt[r][23 - c];
            end
        end
    end

    // ==========================================
    // 5. TASK MÔ PHỎNG GIAO THỨC SPI
    // ==========================================
    task send_spi_byte(input [7:0] data);
        integer bit_idx;
        begin
            for (bit_idx = 7; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                spi_img_mosi = data[bit_idx];
                #20 spi_img_clk = 1;
                #20 spi_img_clk = 0;
            end
        end
    endtask

    // =========================================================================
    // 6. MODULE SNOOPING: CỖ MÁY IN LOG FC2 ĐỒNG BỘ PIPELINE
    // =========================================================================
    
    // Tự tạo thanh ghi trễ 1 nhịp trong Testbench để né lỗi Tối ưu hóa của ModelSim
    reg [4:0]  d1_state;
    reg [9:0]  d1_pixel_cnt;
    reg [15:0] d1_ram_data;
    reg [15:0] d1_wt_data;
    reg        d1_valid_in;
    reg        d1_acc_clr;
    reg        d1_is_fc;

    always @(posedge clk) begin
        d1_state       <= uut.u_fsm.state;
        d1_pixel_cnt   <= uut.u_fsm.pixel_cnt;
        d1_ram_data    <= uut.act_rd_data;
        d1_wt_data     <= uut.wt_data[15:0];
        d1_valid_in    <= uut.valid_in;
        d1_acc_clr     <= uut.acc_clr;
        d1_is_fc       <= uut.is_fc;
    end

    always @(negedge clk) begin 
        // 1. In log MATH: Dùng các tín hiệu đã được trễ 1 nhịp (d1) để khớp với lõi Datapath
        if (d1_is_fc && d1_state == 17 && d1_valid_in) begin
            $display("[FC2-MATH] Neuron  0 | Nhịp: %2d | RAM_Data: %04X | ROM_Weight: %04X | PopCnt: %2d | Acc_Reg: %3d",
                     d1_pixel_cnt - 1, 
                     d1_ram_data, 
                     d1_wt_data, 
                     uut.u_datapath.pop_cnt, 
                     d1_acc_clr ? uut.u_datapath.pop_cnt : (uut.u_datapath.acc_reg + uut.u_datapath.pop_cnt)); 
        end
        
        // 2. In log DECISION: Chỉ in khi có cờ valid_out từ Datapath (Không gọi biến bị ModelSim xóa nữa)
        if (uut.is_fc && uut.u_datapath.valid_out) begin
            $display("[FC2-DECISION] ===> TỔNG CHỐT: %3d | Ngưỡng (Hex): %04X | Polarity: %b | Giá trị Ngưỡng: %0d | BIT ĐẦU RA (KẾT QUẢ): %b", 
                     uut.u_datapath.acc_reg, 
                     uut.u_datapath.thresh_reg, 
                     uut.u_datapath.thresh_reg[15], 
                     uut.u_datapath.thresh_reg[14:0], 
                     uut.datapath_out);
            $display("----------------------------------------------------------------------------------------------------");
        end
    end

    // --- ĐÓN LÕNG KẾT QUẢ CUỐI CÙNG ---
    always @(posedge clk) begin
        if (done) begin
            #10; // Đợi một chút cho tín hiệu ổn định
            $display("\n=======================================================");
            $display("           KET QUA TEST CUOI CUNG (FC 2 TRONG TOP)      ");
            $display("=======================================================");
            $display("Gia tri Ky vong (Golden) : %b (MO MAT)", expected_result);
            $display("Gia tri FPGA tinh toan   : %b", result);
            $display("-------------------------------------------------------");
            
            if (result === expected_result) begin
                $display(">>> XUAT SAC! MANG NEURAL DA CHAY DUNG 100%% TREN TOP LEVEL! <<<");
                $display(">>> KET LUAN: MO MAT (1) - HE THONG HOAT DONG HOAN HAO! <<<");
            end else begin
                $display(">>> THAT BAI O BUC CUOI CUNG! Ket qua cuoi cung bi sai! <<<");
                $display("Hay kiem tra lai xem Polarity hoac Threshold FC2 co bi lech khong.");
            end
            $display("=======================================================\n");
            $finish;
        end
    end

    // ==========================================
    // 7. KỊCH BẢN CHÍNH (MAIN TEST)
    // ==========================================
    integer i_byte;
    initial begin
        rst_n = 0;
        spi_img_clk = 0;
        spi_img_cs = 1;
        spi_img_mosi = 0;

        #100 rst_n = 1;
        #200;

        $display("==================================================");
        $display("    BAT DAU CHAY MO PHONG TOAN MANG (TOP LEVEL)   ");
        $display("==================================================");

        $display("\n[STM32] Dang gui anh (72 bytes) qua SPI...");
        spi_img_cs = 0; 
        #40;
        for (i_byte = 0; i_byte < 72; i_byte = i_byte + 1) begin
            send_spi_byte(spi_tx_buffer[i_byte]);
            #40; 
        end
        spi_img_cs = 1;
        $display("[STM32] Da gui xong! FPGA dang thuc hien suy luan toan mang...");
        $display("Tien trinh: SPI -> CONV1 -> POOL1 -> CONV2 -> POOL2 -> FC1 -> FC2");
        $display("Vui long kien nhan cho doi FSM tinh toan...\n");
        
        // Timeout bảo vệ
        #100000000; 
        $display("\n[LOI] Timeout! Mach bi treo o dau do hoac khong bao gio bat co Done.");
        $stop;
    end

endmodule