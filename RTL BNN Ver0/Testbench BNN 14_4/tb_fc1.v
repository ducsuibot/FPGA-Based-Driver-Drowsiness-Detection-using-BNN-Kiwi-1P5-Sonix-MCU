`timescale 1ns / 1ps

module tb_fc1;

    // --- KHAI BÁO TÍN HIỆU ---
    reg clk;
    reg rst_n;
    reg frame_done;

    reg        spi_we;
    reg [6:0]  spi_addr;
    reg [7:0]  spi_data;

    wire [11:0] wt_addr;
    wire [31:0] wt_data;
    wire [10:0] act_rd_addr, act_wr_addr;
    wire        act_we;
    wire [15:0] act_wr_data, act_rd_data;
    wire [15:0] center_pixel, window_out;
    
    wire        shift_en, is_conv2, is_fc, is_img_read;
    wire [4:0]  pad_x, pad_y, in_ch;
    wire        valid_in, acc_clr, is_acc_done;
    wire [15:0] thresh_val;
    wire        result, done, valid_out_fb, datapath_out;

    // --- INSTANTIATE CÁC MODULE ---
    reg [31:0] flash_mem [0:3000];
    initial $readmemh("bnn_weights_sim.txt", flash_mem);
    assign wt_data = flash_mem[wt_addr];

    control_fsm u_fsm (
        .clk(clk), .rst_n(rst_n), .frame_done(frame_done),
        .valid_out_fb(valid_out_fb), .datapath_out(datapath_out),
        .wt_data(wt_data), .center_pixel(center_pixel), .act_rd_data(act_rd_data),
        .wt_addr(wt_addr), .act_rd_addr(act_rd_addr), .act_wr_addr(act_wr_addr),
        .act_we(act_we), .act_wr_data(act_wr_data),
        .shift_en(shift_en), .is_conv2(is_conv2), .is_fc(is_fc), .is_img_read(is_img_read),
        .pad_x(pad_x), .pad_y(pad_y), .in_ch(in_ch),
        .valid_in(valid_in), .acc_clr(acc_clr), .is_acc_done(is_acc_done),
        .thresh_val(thresh_val), .result(result), .done(done)
    );

    padding_and_buffer u_pad_buf (
        .clk(clk), .rst_n(rst_n), .spi_we(spi_we), .spi_addr(spi_addr), .spi_data(spi_data),
        .rd_addr(act_rd_addr), .rd_data(act_rd_data),
        .wr_en(act_we), .wr_addr(act_wr_addr), .wr_data(act_wr_data),
        .shift_en(shift_en), .is_conv2(is_conv2), .is_img_read(is_img_read),
        .pad_x(pad_x), .pad_y(pad_y), .in_ch(in_ch),
        .window_out(window_out), .center_pixel(center_pixel)
    );

    datapath_core u_datapath (
        .clk(clk), .rst_n(rst_n),
        .valid_in(valid_in), .acc_clr(acc_clr), .is_acc_done(is_acc_done),
        .is_conv(!is_fc), 
        // SỬA Ở ĐÂY: Nếu là FC thì lấy act_rd_data, nếu là CONV thì lấy window_out
        .window_in(is_fc ? act_rd_data : window_out), 
        .wgt_data(wt_data[15:0]), .thresh_val(thresh_val),
        .out_bit(datapath_out), .valid_out(valid_out_fb)
    );

    // --- CLOCK GENERATOR ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // --- KHỞI TẠO VÀ CHẠY MÔ PHỎNG ---
    reg [23:0] text_img [0:23];    
    reg [7:0]  spi_rom [0:71];     
    
    // Đón dữ liệu Golden của FC1 (64 Nơ-ron = 64 values)
    // Đón dữ liệu Golden của FC1 (Đã nén thành 4 Word)
    reg [15:0] golden_mem [0:3];
    
    integer r, c, p_idx;
    integer i;
    
    initial begin
        rst_n = 0;
        frame_done = 0;
        spi_we = 0;
        spi_addr = 0;
        spi_data = 0;
        
        $readmemb("input_image.txt", text_img);
        $readmemh("golden_output_fc1.txt", golden_mem); // Load mảng FC1

        for (r = 0; r < 24; r = r + 1) begin
            for (c = 0; c < 24; c = c + 1) begin
                p_idx = r * 24 + c;
                spi_rom[p_idx / 8][7 - (p_idx % 8)] = text_img[r][23 - c];
            end
        end

        #20;
        rst_n = 1; 
        #20;

        $display("----------------------------------------");
        $display("Dang nap anh vao RAM qua SPI...");
        for (i = 0; i < 72; i = i + 1) begin
            @(posedge clk);
            spi_we = 1;
            spi_addr = i;
            spi_data = spi_rom[i];
        end
        @(posedge clk);
        spi_we = 0;
        $display("Nap hoan tat! Bat dau chay C1 -> P1 -> C2 -> P2 -> FC1...");
        $display("----------------------------------------");

        #10;
        frame_done = 1;
        @(posedge clk);
        frame_done = 0;

        // Timeout chờ đến khi chạy qua cả CONV2 và lên tới FC1
        #30000000; 
        $display("TIMEOUT: Mo phong bi treo hoac dien ra qua lau.");
        $stop;
    end

    // --- LOGIC ĐÓN LÕNG KẾT QUẢ FC1 ---
    integer match_cnt = 0;
    integer err_cnt = 0;
    integer out_idx = 0;
    // =====================================================================
    // --- DEBUG LOGIC CHO LỚP FC1 (SOI TỪNG NHỊP CLOCK) ---
    // =====================================================================
    always @(negedge clk) begin // Dùng negedge để bắt giá trị chốt cuối nhịp
        if (is_fc) begin
            // 1. Theo dõi quá trình tính Popcount từng nhịp (36 nhịp/nơ-ron)
            // 1. Theo dõi quá trình tính Popcount từng nhịp (36 nhịp/nơ-ron)
            if (valid_in) begin
                $display("[FC1-MATH] Neuron %2d | Nhịp (Pxl_cnt): %2d | RAM_Data (POOL2): %04X | ROM_Weight: %04X | PopCnt: %2d | Acc_Reg (Đang cộng): %3d",
                         // SỬA CHỖ NÀY: window_out -> act_rd_data
                         u_fsm.out_ch, u_fsm.pixel_cnt, act_rd_data, wt_data[15:0], u_datapath.pop_cnt, u_datapath.acc_reg);
            end
            
            // 2. Theo dõi lúc chốt kết quả so sánh Threshold (1 nhịp/nơ-ron)
            if (u_datapath.valid_out) begin
                $display("[FC1-DECISION] ===> TỔNG CHỐT: %3d | Ngưỡng (Hex): %04X | Polarity: %b | Giá trị Ngưỡng: %0d | BIT ĐẦU RA: %b", 
                         u_datapath.acc_reg, 
                         u_datapath.thresh_reg, 
                         u_datapath.thresh_reg[15], 
                         u_datapath.thresh_reg[14:0], 
                         datapath_out);
                $display("----------------------------------------------------------------------------------------------------");
            end
        end
    end
    always @(posedge clk) begin
        // FC1 ghi 4 Word (chứa 64 bit) vào địa chỉ 972 đến 975
        if (act_we && (act_wr_addr >= 972) && (act_wr_addr < 976)) begin
            
            out_idx = act_wr_addr - 972;
            
            if (act_wr_data === golden_mem[out_idx]) begin
                match_cnt = match_cnt + 1;
            end else begin
                err_cnt = err_cnt + 1;
                $display("[FAIL] FC1 Chunk %0d | FPGA: %04X | Golden: %04X", out_idx, act_wr_data, golden_mem[out_idx]);
            end

            // Kết thúc ngay khi nhận đủ 4 Word
            if (out_idx >= 3) begin
                #10;
                $display("\n========================================");
                $display("           KET QUA TEST FC 1            ");
                $display("========================================");
                $display("Tong so Word da so sanh: 4 (Chua 64 Nơ-ron)");
                $display("So luong MATCH (Khop)  : %0d", match_cnt);
                $display("So luong LOI           : %0d", err_cnt);
                if (err_cnt == 0) begin
                    $display(">>> TUYET VOI! FC 1 chay chuan xac! <<<");
                end else begin
                    $display(">>> THAT BAI! <<<");
                end
                $display("========================================\n");
                $finish;
            end
        end
    end

endmodule