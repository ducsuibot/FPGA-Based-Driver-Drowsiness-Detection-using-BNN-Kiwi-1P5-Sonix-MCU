`timescale 1ns / 1ps

module tb_pool1;

    // --- 1. KHAI BÁO TÍN HIỆU ---
    reg clk;
    reg rst_n;
    reg frame_done;

    // Tín hiệu giao tiếp SPI (Nạp ảnh)
    reg        spi_we;
    reg [6:0]  spi_addr;
    reg [7:0]  spi_data;

    // Các tín hiệu kết nối nội bộ
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

    // --- 2. INSTANTIATE CÁC MODULE ---
    
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
        .is_conv(!is_fc), // CONV1 và CONV2 đều là 1, FC là 0
        .window_in(window_out), .wgt_data(wt_data[15:0]), .thresh_val(thresh_val),
        .out_bit(datapath_out), .valid_out(valid_out_fb)
    );

    // --- 3. CLOCK GENERATOR (100 MHz) ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // --- 4. KHỞI TẠO VÀ CHẠY MÔ PHỎNG ---
    reg [23:0] text_img [0:23];    
    reg [7:0]  spi_rom [0:71];     
    
    // ĐỔI KÍCH THƯỚC: Pool 1 chỉ có 12x12 = 144 pixel
    reg [15:0] golden_mem [0:143]; 
    
    integer r, c, p_idx;
    integer i;
    
    initial begin
        rst_n = 0;
        frame_done = 0;
        spi_we = 0;
        spi_addr = 0;
        spi_data = 0;
        
        $readmemb("input_image.txt", text_img);
        
        // NẠP FILE GOLDEN POOLING
        $readmemh("golden_output_p1.txt", golden_mem);

        // Nén dữ liệu ảnh
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
        $display("Nap anh hoan tat! Bat dau chay CONV1 va sau do la POOL1...");
        $display("Vui long doi, qua trinh nay se mat mot khoang thoi gian...");
        $display("----------------------------------------");

        #10;
        frame_done = 1;
        @(posedge clk);
        frame_done = 0;

        // Tăng Timeout lên do cần chạy qua cả CONV1 và POOL1
        #300000;
        $display("TIMEOUT: Mo phong bi treo hoac dien ra qua lau.");
        $stop;
    end

    // --- 5. LOGIC ĐÓN LÕNG KẾT QUẢ POOL 1 ---
    integer match_cnt = 0;
    integer err_cnt = 0;
    integer out_idx = 0;

    always @(posedge clk) begin
        // Dải địa chỉ POOL1 nằm từ 648 đến 791 (144 pixels)
        // Các địa chỉ act_wr_addr < 648 (của CONV1) sẽ bị bỏ qua
        if (act_we && (act_wr_addr >= 648) && (act_wr_addr < 792)) begin
            
            out_idx = act_wr_addr - 648; // Map index về 0 -> 143
            
            $display("Checking POOL1 Pixel %0d | Dia chi: %0d | Data: %04X", out_idx, act_wr_addr, act_wr_data);
            
            if (act_wr_data === golden_mem[out_idx]) begin
                match_cnt = match_cnt + 1;
            end else begin
                err_cnt = err_cnt + 1;
                $display("[FAIL] POOL1 Pixel %0d | FPGA: %04X | Golden: %04X", 
                          out_idx, act_wr_data, golden_mem[out_idx]);
            end

            // Kiểm tra điều kiện kết thúc lớp POOL1 (Đã nhận đủ 144 giá trị)
            if (out_idx >= 143) begin
                #10; // Đợi cập nhật log
                $display("\n========================================");
                $display("         KET QUA TEST MAX POOL 1        ");
                $display("========================================");
                $display("Tong so Pixel da so sanh: 144");
                $display("So luong MATCH (Khop)   : %0d", match_cnt);
                $display("So luong LOI            : %0d", err_cnt);
                if (err_cnt == 0) begin
                    $display(">>> TUYET VOI! POOL 1 chay chuan xac! <<<");
                end else begin
                    $display(">>> THAT BAI! Logic Pooling co van de! <<<");
                end
                $display("========================================\n");
                $finish;
            end
        end
    end

endmodule