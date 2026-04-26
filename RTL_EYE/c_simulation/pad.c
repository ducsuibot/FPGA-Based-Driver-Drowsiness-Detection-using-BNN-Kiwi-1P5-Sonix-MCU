#include <stdio.h>

#define SIZE 24

// Giả lập RAM ảnh (BRAM)
int act_ram[576]; 

// Giả lập Line Buffer (lb0, lb1 trong Verilog)
int lb0[24], lb1[24];

// Giả lập Register Window (w00...w22 trong Verilog)
int w00, w01, w02, w10, w11, w12, w20, w21, w22;

// Dữ liệu Filter 0 bác cung cấp
int kernel0[9] = {1,1,0, 1,1,1, 1,0,0}; // 110111100
int thresh0 = 6;
int pol0 = 1;

void shift_data(int new_pixel) {
    // Mô phỏng: always @(posedge clk) if (shift_en)
    // Dịch hàng trên cùng
    w00 = w01; w01 = w02; w02 = lb1[23];
    for(int i=23; i>0; i--) lb1[i] = lb1[i-1];
    
    // Dịch hàng giữa
    w10 = w11; w11 = w12; w12 = lb0[23];
    lb1[0] = lb0[23]; // Dữ liệu từ lb0 tràn lên lb1
    for(int i=23; i>0; i--) lb0[i] = lb0[i-1];
    
    // Dịch hàng dưới cùng (nhận pixel mới từ RAM)
    w20 = w21; w21 = w22; w22 = new_pixel;
    lb0[0] = new_pixel;
}

int main() {
    // --- 1. GIAI ĐOẠN PRE-LOADING (S_PR1) ---
    // Nạp 25 pixel đầu tiên để "điền đầy" băng tải lb0
    for(int i = 0; i < 25; i++) {
        shift_data(act_ram[i]); 
    }
    printf("# [HARDWARE LOG] Ket thuc Pre-loading tai nhip 25.\n");

    // --- 2. GIAI ĐOẠN TINH TOAN (S_CV1) ---
    // Quét toàn bộ ảnh từ (0,0) đến (23,23)
    for(int r = 0; r < SIZE; r++) {
        for(int c = 0; c < SIZE; c++) {
            
            // A. PADDING LOGIC (Mô phỏng module padding_and_buffer)
            // Nếu ở biên thì ép bit về 0, nếu không lấy từ thanh ghi cửa sổ 'w'
            int win[9];
            win[0] = (r==0 || c==0) ? 0 : w00; // Top-Left
            win[1] = (r==0)        ? 0 : w01; // Top-Mid
            win[2] = (r==0 || c==23)? 0 : w02; // Top-Right
            win[3] = (c==0)        ? 0 : w10; // Mid-Left
            win[4] =                     w11; // CENTER PIXEL
            win[5] = (c==23)       ? 0 : w12; // Mid-Right
            win[6] = (r==23|| c==0)? 0 : w20; // Bot-Left
            win[7] = (r==23)       ? 0 : w21; // Bot-Mid
            win[8] = (r==23|| c==23)? 0 : w22; // Bot-Right

            // B. TINH TOAN (Mô phỏng module datapath_core)
            int pop = 0;
            for(int k=0; k<9; k++) {
                if (win[k] == kernel0[k]) pop++; // XNOR + Popcount
            }

            // C. THRESHOLDING
            int bit_out = (pol0 == 1) ? (pop >= thresh0) : (pop <= thresh0);

            // D. DỊCH PIXEL TIẾP THEO (Để chuẩn bị cho nhip sau)
            // act_rd_addr <= pad_y*24 + pad_x + 25
            if ((r*24 + c + 25) < 576) {
                shift_data(act_ram[r*24 + c + 25]);
            }

            // Log chi tiết Pixel đầu tiên
            if(r == 0 && c == 0) {
                printf("# Pixel(0,0): Popcount=%d, Bit_Out=%d\n", pop, bit_out);
            }
        }
    }
    return 0;
}