`timescale 1ns / 1ps

module tb_padding_and_buffer();
    reg clk, rst_n, spi_we, wr_en, shift_en, is_conv2, is_img_read;
    reg [6:0] spi_addr; reg [7:0] spi_data;
    reg [10:0] rd_addr, wr_addr; reg [15:0] wr_data;
    reg [4:0] pad_x, pad_y; reg [3:0] in_ch;
    
    wire [15:0] rd_data, window_out, center_pixel;

    padding_and_buffer dut (
        .clk(clk), .rst_n(rst_n), .spi_we(spi_we), .spi_addr(spi_addr), .spi_data(spi_data),
        .rd_addr(rd_addr), .rd_data(rd_data), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .shift_en(shift_en), .is_conv2(is_conv2), .is_img_read(is_img_read),
        .pad_x(pad_x), .pad_y(pad_y), .in_ch(in_ch),
        .window_out(window_out), .center_pixel(center_pixel)
    );

    initial begin clk = 0; forever #10 clk = ~clk; end

    integer i;
    initial begin
        rst_n = 0; spi_we = 0; wr_en = 0; shift_en = 0;
        is_conv2 = 0; is_img_read = 0; in_ch = 0; pad_x = 0; pad_y = 0; rd_addr = 0;
        #100 rst_n = 1; #20;

        $display("==================================================");
        $display(" BAT DAU TEST: PADDING AND BUFFER (STREAMING FIX)");
        $display("==================================================");

        wr_en <= 1;
        for (i = 0; i < 72; i = i + 1) begin
            @(posedge clk); wr_addr <= i; wr_data <= i + 1;
        end
        @(posedge clk); wr_en <= 0; #50;
        
        // FIX: Bơm liên tục 51 pixel để mồi đầy Line Buffer (Đến tọa độ x=2, y=2)
        $display("-> Dang bom lien tuc 51 pixel de lap day Line Buffer...");
        for (i = 0; i <= 50; i = i + 1) begin
            rd_addr <= i;
            @(posedge clk); 
            @(posedge clk); 
            shift_en <= 1;
            @(posedge clk);
            shift_en <= 0;
        end
        
        #10;
        $display("   [KIEM TRA] Center Pixel (W11) = %0d", dut.center_pixel);
        if (dut.center_pixel === 16'd26) $display("   [PASS] Line Buffer hoat dong hoan hao!");
        else $display("   [FAIL] KET QUA SAI! Mong doi 26, thuc te ra %0d", dut.center_pixel);
        
        $display("==================================================\n");
        $stop;
    end
endmodule