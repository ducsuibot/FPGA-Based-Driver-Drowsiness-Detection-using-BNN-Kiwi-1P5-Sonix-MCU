`timescale 1ns / 1ps

module tb_fc2;

    reg clk;
    reg rst_n;
    reg frame_done;

    wire [11:0] wt_addr;
    wire [31:0] wt_data;
    wire [10:0] act_rd_addr, act_wr_addr;
    wire        act_we;
    wire [15:0] act_wr_data, act_rd_data;
    
    wire        shift_en, is_conv2, is_fc, is_img_read;
    wire [4:0]  pad_x, pad_y, in_ch;
    wire        valid_in, acc_clr, is_acc_done;
    wire [15:0] thresh_val;
    wire        result, done, valid_out_fb, datapath_out;

    // --- 1. KHỞI TẠO ROM ẢO ---
    reg [31:0] flash_mem [0:3000];
    initial $readmemh("bnn_weights_sim.txt", flash_mem);
    assign wt_data = flash_mem[wt_addr];

    // --- 2. KHỞI TẠO RAM ẢO (Chỉ chứa dữ liệu FC1) ---
    reg [15:0] ram [0:1023];
    initial begin
        // Nạp thẳng 4 word từ file golden của FC1 vào đúng tọa độ 972-975
        $readmemh("golden_output_fc1.txt", ram, 972, 975);
    end
    assign act_rd_data = ram[act_rd_addr];

    // --- 3. KẾT NỐI FSM VÀ DATAPATH ---
    control_fsm u_fsm (
        .clk(clk), .rst_n(rst_n), .frame_done(frame_done),
        .valid_out_fb(valid_out_fb), .datapath_out(datapath_out),
        .wt_data(wt_data), .center_pixel(16'd0), .act_rd_data(act_rd_data),
        .wt_addr(wt_addr), .act_rd_addr(act_rd_addr), .act_wr_addr(act_wr_addr),
        .act_we(act_we), .act_wr_data(act_wr_data),
        .shift_en(shift_en), .is_conv2(is_conv2), .is_fc(is_fc), .is_img_read(is_img_read),
        .pad_x(pad_x), .pad_y(pad_y), .in_ch(in_ch),
        .valid_in(valid_in), .acc_clr(acc_clr), .is_acc_done(is_acc_done),
        .thresh_val(thresh_val), .result(result), .done(done)
    );

    // Bỏ qua module padding_and_buffer, trỏ thẳng act_rd_data vào datapath
    datapath_core u_datapath (
        .clk(clk), .rst_n(rst_n),
        .valid_in(valid_in), .acc_clr(acc_clr), .is_acc_done(is_acc_done),
        .is_conv(1'b0), // Ép cứng luôn là lớp FC
        .window_in(act_rd_data), 
        .wgt_data(wt_data[15:0]), .thresh_val(thresh_val),
        .out_bit(datapath_out), .valid_out(valid_out_fb)
    );

    // --- 4. TẠO CLOCK ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // --- 5. KỊCH BẢN CHẠY MÔ PHỎNG (HACK FSM) ---
    initial begin
        rst_n = 0;
        #20;
        rst_n = 1; 
        #20;

        $display("----------------------------------------");
        $display("Bat dau mo phong doc lap lop FC2...");
        
        // ÉP FSM NHẢY THẲNG VÀO TRẠNG THÁI S_FC2 (Giả sử là số 17)
        force u_fsm.state = 17;
        force u_fsm.is_fc = 1;
        #10;
        release u_fsm.state; // Thả ra cho FSM tự chạy tiếp
        release u_fsm.is_fc;
        
        // Timeout
        #1000; 
        $display("TIMEOUT!");
        $stop;
    end

    // --- 6. CỖ MÁY IN LOG (GIỐNG HỆT PYTHON) ---
    // --- 6. CỖ MÁY IN LOG (ĐÃ ĐỒNG BỘ Y HỆT PYTHON) ---
    always @(negedge clk) begin 
        // 1. In log MATH khi FSM đang ở S_FC2 (State 17)
        if (is_fc && u_fsm.state == 17 && valid_in) begin
            $display("[FC2-MATH] Neuron  0 | Nhịp: %2d | RAM_Data: %04X | ROM_Weight: %04X | PopCnt: %2d | Acc_Reg: %3d",
                     u_fsm.pixel_cnt - 1, 
                     act_rd_data, 
                     wt_data[15:0], 
                     u_datapath.pop_cnt, 
                     // Cộng ảo để in ra màn hình giống hệt mạch tư duy của Python
                     u_datapath.acc_reg + u_datapath.pop_cnt); 
        end
        
        // 2. In log DECISION (Bắt độc lập, không phụ thuộc vào State của FSM)
        if (is_fc && u_datapath.valid_out) begin
            $display("[FC2-DECISION] ===> TỔNG CHỐT: %3d | Ngưỡng (Hex): %04X | Polarity: %b | Giá trị Ngưỡng: %0d | BIT ĐẦU RA (KẾT QUẢ): %b", 
                     u_datapath.acc_reg, 
                     u_datapath.thresh_reg, 
                     u_datapath.thresh_reg[15], 
                     u_datapath.thresh_reg[14:0], 
                     datapath_out);
            $display("----------------------------------------------------------------------------------------------------");
        end
    end

    // --- 7. CHỐT HẠ KẾT QUẢ ---
    always @(posedge clk) begin
        if (done) begin
            #10;
            $display("\n=======================================================");
            $display("                HOAN TAT SUY LUAN FPGA!                ");
            $display("=======================================================");
            
            if (result == 1'b1) begin
                $display("=> KET LUAN CUA PHAN CUNG: MO MAT (1)  ---> [ CHUAN XAC! ]");
            end else begin
                $display("=> KET LUAN CUA PHAN CUNG: NHAM MAT (0) ---> [ SAI LECH! ]");
            end
            
            $display("=======================================================\n");
            $finish;
        end
    end

endmodule