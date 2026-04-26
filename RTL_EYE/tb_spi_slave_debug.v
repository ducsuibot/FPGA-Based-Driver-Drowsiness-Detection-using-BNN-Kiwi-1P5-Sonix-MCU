`timescale 1ns / 1ps

module tb_spi_slave_debug();

    // =========================================================================
    // 1. KHAI BÁO TÍN HIỆU
    // =========================================================================
    reg  clk;
    reg  rst_n;
    reg  spi_cs;
    reg  spi_clk;
    reg  spi_mosi;
    wire led_done;

    integer i; // Biến vòng lặp

    // =========================================================================
    // 2. KHỞI TẠO DUT (Device Under Test) - Kết nối module của bạn
    // =========================================================================
    spi_slave_debug #(
        .TOTAL_BYTES(72)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .spi_cs(spi_cs),
        .spi_clk(spi_clk),
        .spi_mosi(spi_mosi),
        .led_done(led_done)
    );

    // =========================================================================
    // 3. TẠO XUNG NHỊP HỆ THỐNG (50MHz -> Chu kỳ 20ns)
    // =========================================================================
    initial begin
        clk = 0;
        forever #10 clk = ~clk; // Đảo trạng thái mỗi 10ns
    end

    // =========================================================================
    // 4. TASK GỬI 1 BYTE QUA SPI (SPI MODE 0)
    // =========================================================================
    task send_spi_byte;
        input [7:0] data;
        integer bit_idx;
        begin
            // Truyền MSB First (Bit 7 xuống Bit 0)
            for (bit_idx = 7; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                spi_mosi = data[bit_idx]; // Đặt dữ liệu lên dây MOSI
                #40;                      // Đợi dữ liệu ổn định (Setup time)
                
                spi_clk = 1;              // Sườn dương SCK (FPGA sẽ đọc ở đây)
                #40;                      // Giữ SCK mức cao (Hold time)
                
                spi_clk = 0;              // Sườn âm SCK
                #40;                      // Giữ SCK mức thấp
            end
        end
    endtask

    // =========================================================================
    // 5. KỊCH BẢN MÔ PHỎNG (STIMULUS)
    // =========================================================================
    initial begin
        // Khởi tạo ghi file Waveform để xem bằng ModelSim hoặc GTKWave
        $dumpfile("tb_spi_waveform.vcd");
        $dumpvars(0, tb_spi_slave_debug);

        // Khởi tạo các tín hiệu ở trạng thái nghỉ
        rst_n    = 0;
        spi_cs   = 1; // CS nghỉ ở mức 1
        spi_clk  = 0; // SPI Mode 0: Clock nghỉ ở mức 0
        spi_mosi = 0;

        $display("---------------------------------------------------");
        $display("[TIME: %0t ns] BAT DAU KHOI DONG HE THONG", $time);

        // Nhả Reset sau 100ns
        #100 rst_n = 1;
        #100;

        // -----------------------------------------------------------
        // KỊCH BẢN: MCU GỬI ĐÚNG 72 BYTES
        // -----------------------------------------------------------
        $display("[TIME: %0t ns] MCU KEO CS XUONG 0 -> BAT DAU GUI", $time);
        spi_cs = 0; 
        #100; // Đợi một chút sau khi kéo CS

        // Vòng lặp gửi 72 bytes (Tôi gửi giá trị từ 0 đến 71 để dễ nhìn trên Waveform)
        for (i = 0; i < 72; i = i + 1) begin
            send_spi_byte(i);
        end

        // -----------------------------------------------------------
        // KẾT THÚC KHUNG TRUYỀN
        // -----------------------------------------------------------
        #100;
        spi_cs = 1; // MCU kéo CS lên 1 để báo kết thúc (Kích hoạt FSM trên FPGA)
        $display("[TIME: %0t ns] MCU KEO CS LEN 1 -> KET THUC GUI", $time);

        // Đợi một chút để FPGA xử lý logic sườn lên của CS
        #100;

        // -----------------------------------------------------------
        // KIỂM TRA KẾT QUẢ
        // -----------------------------------------------------------
        if (led_done === 1'b1) begin
            $display("=> [PASS] led_done = 1. FPGA da nhan va dem dung 72 bytes!");
        end else begin
            $display("=> [FAIL] led_done = 0. Co loi xay ra trong qua trinh dem!");
        end
        $display("---------------------------------------------------");

        // Dừng mô phỏng
        #200 $finish;
    end

endmodule