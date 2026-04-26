#include <stdint.h>

extern uint16_t act_ram[2048];

void run_maxpool1_fsm() {
    // Kích thước ảnh đầu ra POOL1 là 12x12
    for (int pad_y = 0; pad_y < 12; pad_y++) {
        for (int pad_x = 0; pad_x < 12; pad_x++) {
            
            uint16_t pool_buffer[3]; 
            uint16_t pool_data;      

            // ========================================================
            // CHU TRÌNH 6 CLOCK: ĐỌC 4 PIXEL (pixel_cnt từ 0 đến 3)
            // ========================================================
            for (int pixel_cnt = 0; pixel_cnt < 4; pixel_cnt++) {
                
                // Mạch giải mã offset X, Y từ pixel_cnt
                int offset_y = (pixel_cnt >> 1) & 1; // 0, 0, 1, 1
                int offset_x = pixel_cnt & 1;        // 0, 1, 0, 1
                
                // Tính địa chỉ đọc (Base addr CONV1: 72)
                int act_rd_addr = 72 + (pad_y * 2 + offset_y) * 24 + (pad_x * 2 + offset_x);
                
                uint16_t act_rd_data = act_ram[act_rd_addr];
                
                // Hứng dữ liệu vào thanh ghi (Clock 2, 3, 4)
                if (pixel_cnt < 3) {
                    pool_buffer[pixel_cnt] = act_rd_data;
                } 
                // Gộp dữ liệu bằng phép OR (Clock 5)
                else {
                    pool_data = pool_buffer[0] | pool_buffer[1] | pool_buffer[2] | act_rd_data;
                }
            }

            // ========================================================
            // GHI KẾT QUẢ VÀO RAM
            // ========================================================
            // Tính địa chỉ ghi (Base addr POOL1: 648)
            int act_wr_addr = 648 + pad_y * 12 + pad_x;
            
            // act_we = 1;
            act_ram[act_wr_addr] = pool_data;
            
        } 
    } 
}