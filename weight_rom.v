`timescale 1ns / 1ps

module weight_rom (
    input  wire        clk,
    input  wire [11:0] addr, 
    output reg  [31:0] data  
);
    reg [31:0] flash_mem [0:3000];

    initial begin
        $readmemh("bnn_weights_sim.txt", flash_mem);
    end

    always @(posedge clk) begin
        data <= flash_mem[addr];
    end

endmodule


// `timescale 1ns / 1ps

// module weight_rom (
//     input  wire        clk,
//     input  wire [11:0] addr, 
//     output wire [31:0] data  // Đổi thành wire vì data được lái bởi IP Core
// );

//     // Gọi IP Core pROM của Gowin vừa tạo
//     // (Kiểm tra file gowin_prom.v được sinh ra để xem chính xác tên cổng)
//     gowin_prom u_gowin_prom (
//         .clk(clk),
//         .oce(1'b1),     // Output Clock Enable (Luôn bật)
//         .ce(1'b1),      // Chip Enable (Luôn bật)
//         .reset(1'b0),   // Không dùng reset
//         .ad(addr),      // Địa chỉ 12-bit
//         .dout(data)     // Dữ liệu đầu ra 32-bit (đã có sẵn độ trễ 1 chu kỳ)
//     );

// endmodule