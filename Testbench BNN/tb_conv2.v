`timescale 1ns / 1ps

module tb_conv2;

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
    
    // Giả lập ROM Trọng số
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
    
    // Đón dữ liệu Golden của lớp CONV2 (12x12 = 144 pixels)
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
        
        // ĐỌC FILE GOLDEN CỦA LỚP CONV2
        $readmemh("golden_output_l2.txt", golden_mem);

        // Nén dữ liệu ảnh SPI
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
        $display("Nap anh hoan tat! Bat dau chay CONV1 -> POOL1 -> CONV2...");
        $display("Canh bao: CONV2 tinh toan rat lau (quet 3D). Vui long doi khoang vai chuc giay...");
        $display("----------------------------------------");

        #10;
        frame_done = 1;
        @(posedge clk);
        frame_done = 0;

        // Tăng cực đại Timeout để chờ CONV2 tính xong
        #2000000;
        $display("TIMEOUT: Mo phong bi treo hoac dien ra qua lau.");
        $stop;
    end

    // --- 5. LOGIC ĐÓN LÕNG KẾT QUẢ CONV2 (ĐOẠN CODE CỦA BÁC) ---
    integer match_cnt = 0;
    integer err_cnt = 0;
    integer out_idx = 0;

    always @(posedge clk) begin
        // Dải địa chỉ CONV2 nằm từ 792 đến 935 (144 pixels)
        if (act_we && (act_wr_addr >= 792) && (act_wr_addr < 936)) begin
            
            out_idx = act_wr_addr - 792;
            
            if (act_wr_data === golden_mem[out_idx]) begin
                match_cnt = match_cnt + 1;
            end else begin
                err_cnt = err_cnt + 1;
                $display("[FAIL] CONV2 Pixel %0d | FPGA: %04X | Golden: %04X", out_idx, act_wr_data, golden_mem[out_idx]);
            end

            if (out_idx >= 143) begin
                #10;
                $display("\n========================================");
                $display("         KET QUA TEST CONV 2            ");
                $display("========================================");
                $display("Tong so Pixel da so sanh: 144");
                $display("So luong MATCH (Khop)   : %0d", match_cnt);
                $display("So luong LOI            : %0d", err_cnt);
                if (err_cnt == 0) begin
                    $display(">>> TUYET VOI! CONV 2 chay chuan xac! <<<");
                end else begin
                    $display(">>> THAT BAI! Vui long kiem tra lai logic Dual-Threshold hoac 3D Quet. <<<");
                end
                $display("========================================\n");
                $finish;
            end
        end
    end

endmodule