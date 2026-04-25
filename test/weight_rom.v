//`timescale 1ns / 1ps

//module weight_rom (
//    input  wire        clk,
//    input  wire [11:0] addr, 
//    output reg  [31:0] data  
//);
//    reg [31:0] flash_mem [0:3000];

//    initial begin
//        $readmemh("bnn_weights_sim.txt", flash_mem);
//    end

//    always @(posedge clk) begin
//        data <= flash_mem[addr];
//    end

//endmodule


 `timescale 1ns / 1ps

 module weight_rom (
     input  wire        clk,
     input  wire [11:0] addr, 
     output wire [31:0] data  // Đổi thành wire vì data được lái bởi IP Core
 );

     // Gọi IP Core pROM của Gowin vừa tạo
     // (Kiểm tra file gowin_prom.v được sinh ra để xem chính xác tên cổng)

`timescale 1ns / 1ps

module weight_rom (
    input  wire        clk,
    input  wire [11:0] addr, 
    output wire [31:0] data  
);

    // Gọi đúng tên module chữ hoa từ file IP
    Gowin_ROM u_gowin_prom (
        .clk(clk),
        .oce(1'b1),            // BẬT LÊN 1 để Latch trong suốt -> Dữ liệu chạy ra trong 1 Clock
        .ce(1'b1),             // Chip Enable luôn bật
        .reset(1'b0),          
        .ad(addr[10:0]),       // Truyền 11 bit địa chỉ (quét 2048 ô nhớ)
        .dout(data)            
    );

endmodule