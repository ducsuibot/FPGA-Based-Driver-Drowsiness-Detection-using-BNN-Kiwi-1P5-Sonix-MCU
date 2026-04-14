`timescale 1ns / 1ps

module weight_rom (
    input  wire        clk,
    input  wire [11:0] addr, 
    // SỬA: Đổi reg thành wire
    output wire [31:0] data  
);
    reg [31:0] flash_mem [0:3000];

    initial begin
        // Đọc file Hex thuần 32-bit (8 ký tự)
        $readmemh("bnn_weights_sim.txt", flash_mem);
    end

    // SỬA: Biến ROM thành Bất đồng bộ (0-cycle latency) giống hệt Testbench
    assign data = flash_mem[addr];

endmodule