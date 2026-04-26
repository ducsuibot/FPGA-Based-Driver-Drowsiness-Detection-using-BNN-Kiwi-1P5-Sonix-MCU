#include <stdint.h>
#include <stdbool.h>

extern uint16_t act_ram[2048];       // BRAM 
extern uint32_t weight_rom[3000];    // ROM 

// Thanh ghi nội bộ cho Line Buffer
uint16_t lb0[12] = {0}, lb1[12] = {0}; 
uint16_t w00=0, w01=0, w02=0, w10=0, w11=0, w12=0, w20=0, w21=0, w22=0;

// Hàm dịch chuyển cửa sổ kích thước 12 (CONV2)
void shift_window_conv2(uint16_t new_data) {
    w20 = w21; w21 = w22; w22 = new_data;
    w10 = w11; w11 = w12; w12 = lb0[11];
    w00 = w01; w01 = w02; w02 = lb1[11];
    
    for (int i = 11; i > 0; i--) {
        lb0[i] = lb0[i-1];
        lb1[i] = lb1[i-1];
    }
    lb0[0] = new_data;
    lb1[0] = lb0[11];
}

void run_conv2_fsm() {
    int wt_addr = 16;             // ROM offset cho CONV2 (theo FSM)
    int act_wr_addr = 792;        // Địa chỉ lưu Output CONV2
    int rd_addr = 648;            // Địa chỉ đọc Input (POOL1 Output)

    // =========================================================
    // 1. PRE-READ (Nạp đà 1 hàng của Feature Map 12x12)
    // FSM: CONV2_PRE_ADDR -> CONV2_PRE_CHECK
    // =========================================================
    for (int pixel_cnt = 0; pixel_cnt < 13; pixel_cnt++) {
        uint16_t raw_16b = act_ram[rd_addr++];
        shift_window_conv2(raw_16b);
    }

    // =========================================================
    // 2. MAIN SPATIAL LOOP (Quét ảnh 12x12)
    // FSM: CONV2_ADDR -> CONV2_CALC
    // =========================================================
    for (int pad_y = 0; pad_y < 12; pad_y++) {
        for (int pad_x = 0; pad_x < 12; pad_x++) {
            
            // Look-ahead Read & Shift
            int fetch_addr = 648 + pad_y * 12 + pad_x + 13;
            uint16_t new_px = (fetch_addr < 792) ? act_ram[fetch_addr] : 0;
            shift_window_conv2(new_px);

            uint16_t bg_data = 0; // Thanh ghi gom 16 kênh đầu ra

            // FSM: Chạy 256 nhịp (16 out_ch * 16 in_ch)
            for (int out_ch = 0; out_ch < 16; out_ch++) {
                
                int acc_reg = 0; // Bộ tích lũy (Datapath)
                uint16_t thresh_val = 0;
                
                for (int in_ch = 0; in_ch < 16; in_ch++) {
                    
                    // Đọc trọng số từ ROM
                    uint32_t flash_word = weight_rom[wt_addr++];
                    uint16_t wgt_data   = flash_word & 0xFFFF;
                    
                    // Lấy Threshold ở nhịp cuối của In_channel (Nhịp thứ 15)
                    if (in_ch == 15) {
                        thresh_val = (flash_word >> 16) & 0xFFFF;
                    }

                    // Trích xuất cửa sổ 9-bit cho kênh in_ch hiện tại (Mạch MUX Padding)
                    bool pad_top = (pad_y == 0), pad_bottom = (pad_y == 11);
                    bool pad_left = (pad_x == 0), pad_right = (pad_x == 11);
                    
                    uint16_t win_1b = 0;
                    win_1b |= ((pad_top || pad_left)     ? 0 : ((w00 >> in_ch) & 1)) << 8;
                    win_1b |= ((pad_top)                 ? 0 : ((w01 >> in_ch) & 1)) << 7;
                    win_1b |= ((pad_top || pad_right)    ? 0 : ((w02 >> in_ch) & 1)) << 6;
                    win_1b |= ((pad_left)                ? 0 : ((w10 >> in_ch) & 1)) << 5;
                    win_1b |= (                                ((w11 >> in_ch) & 1)) << 4; // Center
                    win_1b |= ((pad_right)               ? 0 : ((w12 >> in_ch) & 1)) << 3;
                    win_1b |= ((pad_bottom || pad_left)  ? 0 : ((w20 >> in_ch) & 1)) << 2;
                    win_1b |= ((pad_bottom)              ? 0 : ((w21 >> in_ch) & 1)) << 1;
                    win_1b |= ((pad_bottom || pad_right) ? 0 : ((w22 >> in_ch) & 1)) << 0;

                    // Phép tính XNOR + Popcount 9-bit
                    uint16_t xnor_res = ~(win_1b ^ wgt_data);
                    int pop_cnt = 0;
                    for(int i = 0; i < 9; i++) {
                        pop_cnt += (xnor_res >> i) & 1;
                    }
                    
                    // Cộng dồn vào thanh ghi
                    acc_reg += pop_cnt;
                }
                
                // =========================================================
                // 3. THRESHOLD & STORE (Đóng gói kết quả)
                // =========================================================
                bool polarity = (thresh_val >> 15) & 1;
                int threshold_val = thresh_val & 0x7FFF;
                
                bool datapath_out;
                if (polarity) datapath_out = (acc_reg >= threshold_val);
                else          datapath_out = (acc_reg <= threshold_val);
                
                // Bit-packing (Dịch bit vào bg_buffer)
                bg_data = (datapath_out << 15) | (bg_data >> 1);
            }
            
            // Ghi 1 cục 16-bit xuống BRAM
            act_ram[act_wr_addr++] = bg_data;
        }
    }
}