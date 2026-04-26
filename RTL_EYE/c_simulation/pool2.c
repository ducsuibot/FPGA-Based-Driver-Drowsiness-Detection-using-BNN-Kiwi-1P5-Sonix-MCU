#include <stdint.h>
#include <stdio.h>

// Khai báo RAM toàn cục giống như act_ram trên FPGA
extern uint16_t act_ram[2048];

void run_maxpool2_fsm() {
    printf("\n# >>> BẮT ĐẦU LAYER POOL2 (Mô phỏng FSM Verilog) <<<\n");

    // Kích thước ảnh đầu ra POOL2 là 6x6 (Từ bản đồ 12x12 của CONV2)
    for (int pad_y = 0; pad_y < 6; pad_y++) {
        for (int pad_x = 0; pad_x < 6; pad_x++) {
            
            // Khai báo các thanh ghi nội bộ của module
            uint16_t pool_buffer[3] = {0, 0, 0}; 
            uint16_t pool_data = 0;      
            uint16_t act_rd_data = 0;

            // ========================================================
            // CHU TRÌNH 6 CLOCK (Mô phỏng pixel_cnt từ 0 đến 5)
            // ========================================================
            for (int pixel_cnt = 0; pixel_cnt <= 5; pixel_cnt++) {
                
                // ----------------------------------------------------
                // CLOCK 0 -> 3: Phát địa chỉ đọc (act_rd_addr)
                // ----------------------------------------------------
                if (pixel_cnt < 4) {
                    // Mạch giải mã offset X, Y bằng bitwise giống Verilog: 
                    // pixel_cnt[1] và pixel_cnt[0]
                    int offset_y = (pixel_cnt >> 1) & 1; // Bit 1
                    int offset_x = pixel_cnt & 1;        // Bit 0
                    
                    // Tính địa chỉ đọc (Base addr CONV2: 792)
                    // Bản đồ CONV2 có chiều ngang là 12 pixel
                    int act_rd_addr = 792 + (pad_y * 2 + offset_y) * 12 + (pad_x * 2 + offset_x);
                    
                    // Mô phỏng độ trễ của RAM: Phát địa chỉ xong, nhịp sau mới có data
                    // Trong C, ta đọc luôn để chuẩn bị cho nhịp sau
                    act_rd_data = act_ram[act_rd_addr]; 
                }

                // ----------------------------------------------------
                // CLOCK 2 -> 4: Lưu dữ liệu vào thanh ghi (pipeline)
                // ----------------------------------------------------
                if (pixel_cnt >= 2 && pixel_cnt <= 4) {
                    // Chú ý: Trong Verilog thực tế, act_rd_data này là kết quả 
                    // của địa chỉ phát ra từ 2 nhịp trước do delay của Block RAM.
                    pool_buffer[pixel_cnt - 2] = act_rd_data;
                }

                // ----------------------------------------------------
                // CLOCK 5: Chốt kết quả (pool_we = 1) và tăng tọa độ
                // ----------------------------------------------------
                if (pixel_cnt == 5) {
                    // Gộp 4 pixel bằng phép OR (Mạng BNN)
                    pool_data = pool_buffer[0] | pool_buffer[1] | pool_buffer[2] | act_rd_data;
                    
                    // Tính địa chỉ ghi (Base addr POOL2: 936)
                    // Bản đồ POOL2 có chiều ngang là 6 pixel
                    int act_wr_addr = 936 + pad_y * 6 + pad_x;
                    
                    // Ghi vào RAM (Mô phỏng pool_we = 1)
                    act_ram[act_wr_addr] = pool_data;

                    // In Log báo cáo giống format FPGA
                    printf("# POOL2 Pixel [%d,%d] | Ghi vào Addr: %d | Data_Out (Hex): %04X\n", 
                           pad_y, pad_x, act_wr_addr, pool_data);
                }
            } // Hết 1 chu trình 6 Clock
            
        } 
    } 
    printf("# >>> HOÀN TẤT LAYER POOL2 <<<\n");
}