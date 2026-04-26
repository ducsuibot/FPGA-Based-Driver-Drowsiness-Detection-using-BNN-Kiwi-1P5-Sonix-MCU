`timescale 1ns / 1ps

module tb_datapath_core();

    // ==========================================
    // 1. KHAI BÁO TÍN HIỆU
    // ==========================================
    reg         clk;
    reg         rst_n;
    reg         valid_in;
    reg         acc_clr;
    reg         is_acc_done;
    reg  [15:0] window_in;
    reg  [15:0] wgt_data;
    reg  [15:0] thresh_val;
    
    wire        out_bit;
    wire        valid_out;

    // ==========================================
    // 2. KHỞI TẠO MODULE (DUT)
    // ==========================================
    datapath_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .acc_clr(acc_clr),
        .is_acc_done(is_acc_done),
        .window_in(window_in),
        .wgt_data(wgt_data),
        .thresh_val(thresh_val),
        .out_bit(out_bit),
        .valid_out(valid_out)
    );

    // ==========================================
    // 3. TẠO XUNG CLOCK (50MHz)
    // ==========================================
    initial begin
        clk = 0;
        forever #10 clk = ~clk; 
    end

    // ==========================================
    // 4. KỊCH BẢN KIỂM TRA (MAIN TEST)
    // ==========================================
    // Giả lập tính toán CONV1: 9 pixel * 9 weight
    // Input : 0000000000000101 (chỉ quan tâm 9 bit cuối: 0 0 0, 0 0 0, 1 0 1)
    // Weight: 0000000000000111 (chỉ quan tâm 9 bit cuối: 0 0 0, 0 0 0, 1 1 1)
    // Phép toán Popcount( ~(Input ^ Weight) ) với 16 bit
    // XNOR 16 bit: ~(0x0005 ^ 0x0007) = ~(0x0002) = 0xFFFD
    // Popcount(0xFFFD) = 15 bit '1'
    
    // Golden Output:
    // Tổng Popcount = 15 (vì ta giả lập 1 nhịp là đủ 16-bit)
    // Threshold = 10.
    // Kết quả mong muốn: 15 >= 10 -> 1 (Mở mắt)

    initial begin
        // Trạng thái ban đầu
        rst_n = 0; valid_in = 0; acc_clr = 0; is_acc_done = 0;
        window_in = 16'd0; wgt_data = 16'd0; thresh_val = 16'd0;
        
        #100 rst_n = 1;
        #20;

        $display("==================================================");
        $display(" BAT DAU TEST: DATAPATH CORE");
        $display("==================================================");

        // Kích hoạt tính toán 1 nhịp (vì datapath tính 16 bit/nhịp)
        // Nếu muốn test nhiều nhịp, bạn tạo vòng lặp ở đây
        @(posedge clk);
        valid_in <= 1'b1;
        acc_clr  <= 1'b1; // Reset Accumulator
        is_acc_done <= 1'b1; // Coi như tích lũy xong trong 1 nhịp
        window_in <= 16'h0005; 
        wgt_data  <= 16'h0007; 
        thresh_val <= 16'h800A; // Sign=1 (8000), Thresh=10 (000A)
        
        @(posedge clk);
        valid_in <= 1'b0; // Tắt tín hiệu vào

        // Chờ Datapath xử lý xong (Trễ 2 Clock Pipeline)
        wait(valid_out == 1'b1);
        @(posedge clk); // Đợi thêm 1 clock để out_bit ổn định

        // Kiểm tra kết quả
        $display("   [TINH TOAN] Popcount = %0d, Threshold = %0d", dut.acc_reg, thresh_val[14:0]);
        if (out_bit === 1'b1) begin
            $display("   [PASS] Ket qua dung: %0d", out_bit);
        end else begin
            $display("   [FAIL] KET QUA SAI! Mong doi 1, thuc te ra %0b", out_bit);
        end

        $display("==================================================\n");
        $stop;
    end
endmodule