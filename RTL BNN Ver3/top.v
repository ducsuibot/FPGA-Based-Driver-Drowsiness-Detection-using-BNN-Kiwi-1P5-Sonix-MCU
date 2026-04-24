`timescale 1ns / 1ps

module top (
    input  wire clk, 
    input  wire rst_n,
    input  wire spi_img_clk, 
    input  wire spi_img_cs, 
    input  wire spi_img_mosi,
    output wire spi_miso,
    output wire result,      // <-- Chân nối ra ngoài (VD: LED)
    output wire done         
);

    wire w_busy, w_result;
    wire [11:0] w_current_pop;  // <--- THÊM
    wire [5:0]  w_fc2_pop;      // <--- THÊM
    
    // [THÊM MỚI]: Nối tín hiệu kết quả từ bên trong chip ra ngoài chân vật lý
    assign result = w_result;


    // =========================================================================
    // KHAI BÁO DÂY KẾT NỐI (WIRES)
    // =========================================================================
    wire        spi_valid;
    wire        frame_done;
    wire [7:0]  spi_data; 
    wire [6:0]  spi_addr;
    wire [11:0] wt_addr; 
    wire [31:0] wt_data;
    
    wire [10:0] act_rd_addr;
    wire [10:0] act_wr_addr;  
    wire [15:0] act_rd_data;
    wire [15:0] act_wr_data;
    
    wire        act_we;
    wire        shift_en;
    wire        is_conv2;
    wire        is_fc;
    wire        is_img_read;
    
    wire [4:0]  pad_x;
    wire [4:0]  pad_y; 
    wire [4:0]  in_ch; 
    
    wire [15:0] window_out;
    wire [15:0] center_pixel;
    
    wire        valid_in;
    wire        acc_clr;
    wire        is_acc_done;
    wire        valid_out;
    wire        datapath_out;
    wire [15:0] thresh_val;

    // =========================================================================
    // 1. GIAO TIẾP SPI
    // =========================================================================
   spi_slave u_spi (
        .clk        (clk), 
        .rst_n      (rst_n), 
        .spi_clk    (spi_img_clk), 
        .spi_cs     (spi_img_cs), 
        .spi_mosi   (spi_img_mosi),
        .spi_miso   (spi_miso),
        .rx_valid   (spi_valid), 
        .rx_data    (spi_data), 
        .rx_addr    (spi_addr), 
        .frame_done (frame_done),
        .busy_in    (w_busy),       // <-- [ĐÃ SỬA]: Thành w_busy
        .result_in  (w_result),
        .pop_in     (w_fc2_pop)     // <--- Nối vào SPI
    );

    // =========================================================================
    // 2. BỘ NHỚ TRỌNG SỐ (ROM)
    // =========================================================================
    weight_rom u_flash (
        .clk        (clk), 
        .addr       (wt_addr), 
        .data       (wt_data)
    );

    // =========================================================================
    // 3. KHỐI ĐỆM VÀ QUÉT CỬA SỔ (RAM + LINE BUFFER)
    // =========================================================================
    padding_and_buffer u_pad_buf (
        .clk          (clk), 
        .rst_n        (rst_n), 
        .spi_we       (spi_valid), 
        .spi_addr     (spi_addr), 
        .spi_data     (spi_data),
        .rd_addr      (act_rd_addr), 
        .rd_data      (act_rd_data),
        .wr_en        (act_we), 
        .wr_addr      (act_wr_addr), 
        .wr_data      (act_wr_data),
        .shift_en     (shift_en), 
        .pad_x        (pad_x), 
        .pad_y        (pad_y), 
        .in_ch        (in_ch),
        .is_conv2     (is_conv2), 
        .is_img_read  (is_img_read),
        .window_out   (window_out), 
        .center_pixel (center_pixel)     
    );

    // =========================================================================
    // 4. BỘ TÍNH TOÁN CỐT LÕI (DATAPATH)
    // =========================================================================
    // ĐÃ XÓA KHỐI ĐẢO BIT: Vì trọng số FC1 đã được transpose bằng Python.
    wire [15:0] datapath_in = is_fc ? act_rd_data : window_out;
    
    datapath_core u_datapath (
        .clk         (clk), 
        .rst_n       (rst_n),
        .valid_in    (valid_in), 
        .acc_clr     (acc_clr), 
        .is_acc_done (is_acc_done),
        .is_conv     (!is_fc), 
        .window_in   (datapath_in), 
        .wgt_data    (wt_data[15:0]),
        .thresh_val  (thresh_val),
        .out_bit     (datapath_out), 
        .valid_out   (valid_out),
        .current_pop (w_current_pop) // <--- Lôi từ Datapath ra       
    );

    // =========================================================================
    // 5. MÁY TRẠNG THÁI ĐIỀU KHIỂN (FSM)
    // =========================================================================
    control_fsm u_fsm (
        .clk          (clk), 
        .rst_n        (rst_n), 
        .frame_done   (frame_done), 
        .valid_out_fb (valid_out), 
        .datapath_out (datapath_out),
        .wt_data      (wt_data), 
        .center_pixel (center_pixel), 
        .act_rd_data  (act_rd_data),
        .wt_addr      (wt_addr), 
        .act_rd_addr  (act_rd_addr), 
        .act_wr_addr  (act_wr_addr), 
        .act_we       (act_we), 
        .act_wr_data  (act_wr_data),
        .shift_en     (shift_en), 
        .pad_x        (pad_x), 
        .pad_y        (pad_y), 
        .in_ch        (in_ch),
        .valid_in     (valid_in), 
        .acc_clr      (acc_clr), 
        .is_acc_done  (is_acc_done),
        .is_conv2     (is_conv2), 
        .is_fc        (is_fc), 
        .is_img_read  (is_img_read),
        .thresh_val   (thresh_val), 
        .result       (w_result), 
        .done         (done),
        .busy         (w_busy),      // <-- [ĐÃ SỬA]: Thành w_busy
        .current_pop (w_current_pop), // <--- Nối vào FSM
        .fc2_pop     (w_fc2_pop)      // <--- Lấy từ FSM ra
    );
   
    
endmodule