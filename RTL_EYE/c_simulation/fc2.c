#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

// Giả lập hệ thống nhớ
extern uint16_t act_ram[2048];   // Chứa dữ liệu (Act)
extern uint32_t flash_mem[3000]; // Chứa Trọng số (Weights) - 32-bit mỗi word

// Các thanh ghi Pipeline của Datapath
uint32_t wt_data;
uint16_t act_rd_data;
uint16_t acc_reg = 0;
uint16_t thresh_reg = 0;

// Hàm đếm số bit 1 trong một số 16-bit (Dùng chung)
int popcount16(uint16_t val) {
    int count = 0;
    for (int i = 0; i < 16; i++) {
        if ((val >> i) & 1) count++;
    }
    return count;
}

// Hàm thực hiện phép XNOR-Popcount (Dùng chung)
int xnor_popcount(uint16_t act, uint16_t wt) {
    uint16_t xnor_val = ~(act ^ wt);
    return popcount16(xnor_val);
}

void run_fc2_fsm() {
    printf("\n# >>> LAYER 4: FULLY CONNECTED 2 (Lop chot ha) <<<\n");

    // Địa chỉ bắt đầu của Trọng số FC2 (Kế thừa từ state WAIT_SYNC trong Verilog)
    int wt_addr = 2576; 
    
    acc_reg = 0;
    uint16_t final_thresh = 0;
    uint8_t out_bit = 0;

    // ========================================================
    // CHU TRÌNH 6 CLOCK (pixel_cnt từ 0 đến 5)
    // ========================================================
    for (int pixel_cnt = 0; pixel_cnt <= 5; pixel_cnt++) {
        
        // ----------------------------------------------------
        // 1. QUẢN LÝ ĐỊA CHỈ & PRE-FETCH
        // ----------------------------------------------------
        // Phát địa chỉ đọc 64 bit từ FC1 (Gồm 4 word 16-bit ở addr 972 -> 975)
        if (pixel_cnt < 4) {
            int act_rd_addr = 972 + pixel_cnt;
            act_rd_data = act_ram[act_rd_addr]; // Hứng dữ liệu (trễ 1 nhịp)
        }

        // Phát địa chỉ đọc Trọng số (Weight)
        if (pixel_cnt == 0) {
            // Nhịp 0: Không tăng wt_addr (Dùng luôn 2576)
            wt_data = flash_mem[wt_addr]; 
        } 
        else if (pixel_cnt >= 1 && pixel_cnt <= 3) {
            // Nhịp 1..3: Tăng dần để lấy trọng số (2577, 2578, 2579)
            wt_addr++;
            wt_data = flash_mem[wt_addr];
        }

        // ----------------------------------------------------
        // 2. DATAPATH: XNOR-POPCOUNT VÀ TÍCH LŨY (ACC)
        // ----------------------------------------------------
        // valid_in = 1 ở nhịp 1 đến 4 (Tổng cộng 4 nhịp tính toán)
        bool valid_in = (pixel_cnt >= 1 && pixel_cnt <= 4);
        
        if (valid_in) {
            uint16_t wt_16b = (uint16_t)(wt_data & 0xFFFF);
            uint16_t cur_thresh = (uint16_t)((wt_data >> 16) & 0x7FFF);
            
            // Tính Popcount cho khối 16-bit hiện tại
            int pop_cnt = xnor_popcount(act_rd_data, wt_16b);

            // Tích lũy
            if (pixel_cnt == 1) { // acc_clr = 1 tại nhịp 1
                acc_reg = pop_cnt; // Nạp đè
            } else {
                acc_reg += pop_cnt; // Cộng dồn (Nhịp 2, 3, 4)
            }
            
            // Lấy Threshold mới nhất
            final_thresh = cur_thresh;
        }

        // ----------------------------------------------------
        // 3. CHỐT KẾT QUẢ VÀ IN LOG (is_acc_done)
        // ----------------------------------------------------
        if (pixel_cnt == 4) { // is_acc_done = 1
            // Tính toán Bit Out cuối cùng của toàn mạng
            out_bit = (acc_reg >= final_thresh) ? 1 : 0;

            // In log kết luận của FPGA
            printf("# FINAL DECISION | Popcount: %d/64 | Threshold: %d -> RESULT: %d\n", 
                   acc_reg, final_thresh, out_bit);
        }

        // ----------------------------------------------------
        // 4. CHUYỂN TRẠNG THÁI (DONE)
        // ----------------------------------------------------
        if (pixel_cnt == 5) {
            // Trong Verilog: state <= DONE;
            // Dừng module
            break;
        }
    }
}