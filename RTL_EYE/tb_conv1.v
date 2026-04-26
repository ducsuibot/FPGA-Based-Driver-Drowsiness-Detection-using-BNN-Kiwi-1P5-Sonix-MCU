`timescale 1ns / 1ps

module tb_conv1;

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
    
    // Giả lập ROM Trọng số (Lấy trực tiếp từ file bác đóng gói)
    // Gọi trực tiếp module phần cứng
    weight_rom u_flash (
        .clk        (clk), 
        .addr       (wt_addr), 
        .data       (wt_data)
    );

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
        .pad_x(pad_x), .pad_y(pad_y), .in_ch(in_ch), // Đã sửa lỗi đón dây 5-bit
        .window_out(window_out), .center_pixel(center_pixel)
    );

    datapath_core u_datapath (
        .clk(clk), .rst_n(rst_n),
        .valid_in(valid_in), .acc_clr(acc_clr), .is_acc_done(is_acc_done),
        .is_conv(1'b1), // Luôn là 1 cho CONV1
        .window_in(window_out), .wgt_data(wt_data[15:0]), .thresh_val(thresh_val),
        .out_bit(datapath_out), .valid_out(valid_out_fb)
    );

    // --- 3. CLOCK GENERATOR (100 MHz) ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // --- 4. KHỞI TẠO VÀ CHẠY MÔ PHỎNG ---
    reg [23:0] text_img [0:23];    // Mảng đọc ảnh nhị phân từ file txt
    reg [7:0]  spi_rom [0:71];     // Mảng nén 8 pixel thành 1 byte để nạp SPI
    reg [15:0] golden_mem [0:575]; // Mảng chứa Golden Output
    
    integer r, c, p_idx;
    integer i;
    
    initial begin
        // Khởi tạo hệ thống
        rst_n = 0;
        frame_done = 0;
        spi_we = 0;
        spi_addr = 0;
        spi_data = 0;
        
        // Đọc file đầu vào
        $readmemb("input_image.txt", text_img);
        $readmemh("golden_output_l1.txt", golden_mem);

        // Nén dữ liệu ảnh: Mỗi dòng 24 ký tự -> Tách thành từng bit nạp vào spi_rom
        for (r = 0; r < 24; r = r + 1) begin
            for (c = 0; c < 24; c = c + 1) begin
                p_idx = r * 24 + c;
                // Cột c trong file text (bên trái) tương ứng với bit cao nhất (23-c) của readmemb
                spi_rom[p_idx / 8][7 - (p_idx % 8)] = text_img[r][23 - c];
            end
        end

        #20;
        rst_n = 1; // Thả Reset
        #20;

        // Mô phỏng STM32 nạp ảnh vào FPGA qua SPI (72 bytes)
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
        $display("Nap anh hoan tat! Bat dau tinh toan FSM.");
        $display("----------------------------------------");

        // Kích hoạt FSM
        #10;
        frame_done = 1;
        @(posedge clk);
        frame_done = 0;

        // Đợi một khoảng thời gian dài làm Timeout (đề phòng FSM kẹt)
        #2000000;
        $display("TIMEOUT: Mo phong bi treo hoac dien ra qua lau.");
        $stop;
    end

    // --- 5. LOGIC THEO DÕI VÀ SO SÁNH KẾT QUẢ ---
    integer match_cnt = 0;
    integer err_cnt = 0;
    integer out_idx = 0;

    always @(posedge clk) begin
        if (act_we && (act_wr_addr >= 72) && (act_wr_addr < 648)) begin
            out_idx = act_wr_addr - 72;
            
            // In log để bác theo dõi tiến độ
            $display("Checking Pixel %0d | Data: %04X", out_idx, act_wr_data);
            
            if (act_wr_data === golden_mem[out_idx]) begin
                match_cnt = match_cnt + 1;
            end else begin
                err_cnt = err_cnt + 1;
            end

            // Cải tiến điều kiện dừng: Sử dụng >= để tránh trượt nhịp
            if (out_idx >= 575) begin
                #10; // Đợi thêm 1 chút để dữ liệu kịp cập nhật
                $display("\n========================================");
                $display("           KET QUA TEST CONV 1          ");
                $display("========================================");
                $display("Tong so Pixel da so sanh: 576");
                $display("So luong MATCH (Khop)   : %0d", match_cnt);
                $display("So luong LOI            : %0d", err_cnt);
                $display("========================================\n");
                $finish; // Dùng finish để kết thúc hẳn mô phỏng
            end
        end
    end


endmodule