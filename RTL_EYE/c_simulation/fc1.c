#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

// Kích thước của FC1
#define POOL2_PIXELS 36
#define FC1_OUT_NODES 64

// Giả lập hệ thống nhớ và thanh ghi
extern uint16_t act_ram[2048]; // Chứa dữ liệu (Act)
extern uint32_t flash_mem[3000]; // Chứa Trọng số (Weights) - 32-bit mỗi word

// Các thanh ghi Pipeline của Datapath
uint32_t wt_data;
uint16_t act_rd_data;
uint16_t acc_reg = 0;
uint16_t thresh_reg = 0;

// Hàm đếm số bit 1 trong một số 16-bit (Popcount mô phỏng phần cứng)
int popcount16(uint16_t val) {
    int count = 0;
    for (int i = 0; i < 16; i++) {
        if ((val >> i) & 1) count++;
    }
    return count;
}

// Hàm thực hiện phép XNOR-Popcount giữa act (16 bit) và weight (16 bit)
int xnor_popcount(uint16_t act, uint16_t wt) {
    // XNOR 16-bit: ~(act ^ wt)
    // Lưu ý: Trong mạng BNN thực tế, bit 0 đại diện cho -1, bit 1 đại diện cho +1
    // Phép toán chuẩn: popcount(~(act ^ wt))
    uint16_t xnor_val = ~(act ^ wt);
    return popcount16(xnor_val);
}

void run_fc1_fsm() {
    printf("\n# >>> BẮT ĐẦU LAYER 3: FC1 (64 Nodes) <<<\n");

    int wt_addr = 272; // Địa chỉ base của trọng số FC1 (Theo code của bạn)

    // Quét qua 64 nơ-ron đầu ra
    for (int out_ch = 0; out_ch < 64; out_ch++) {
        
        acc_reg = 0; // Xóa thanh ghi tích lũy cho nơ-ron mới (acc_clr)
        uint16_t final_thresh = 0;
        uint8_t out_bit = 0;

        // ========================================================
        // CHU TRÌNH 38 CLOCK (pixel_cnt từ 0 đến 37)
        // ========================================================
        for (int pixel_cnt = 0; pixel_cnt <= 37; pixel_cnt++) {
            
            // ----------------------------------------------------
            // 1. QUẢN LÝ ĐỊA CHỈ & PRE-FETCH
            // ----------------------------------------------------
            // Phát địa chỉ đọc dữ liệu ảnh (Act) từ POOL2
            if (pixel_cnt < 36) {
                int act_rd_addr = 936 + pixel_cnt;
                act_rd_data = act_ram[act_rd_addr]; // Hứng dữ liệu (Mô phỏng trễ 1 nhịp)
            }

            // Phát địa chỉ đọc Trọng số (Weight)
            // Lấy 32 bit Weight (gồm 16 bit Weight, 15 bit Thresh, 1 bit Polarity)
            if (pixel_cnt == 0) {
                // Nhịp 0: Không tăng wt_addr cho Node 0, nhưng tăng cho các Node sau (do kế thừa)
                if (out_ch > 0) wt_addr++; 
                wt_data = flash_mem[wt_addr]; 
            } 
            else if (pixel_cnt >= 1 && pixel_cnt <= 35) {
                // Nhịp 1-35: Tăng dần để lấy trọng số cho từng pixel
                wt_addr++;
                wt_data = flash_mem[wt_addr];
            }

            // ----------------------------------------------------
            // 2. DATAPATH: XNOR-POPCOUNT VÀ TÍCH LŨY (ACC)
            // ----------------------------------------------------
            // valid_in = 1 ở nhịp 1 đến 36 (trễ 1 nhịp so với lệnh cấp addr ở nhịp 0-35)
            bool valid_in = (pixel_cnt >= 1 && pixel_cnt <= 36);
            
            if (valid_in) {
                // Bóc tách 32-bit Weight Word
                uint16_t wt_16b = (uint16_t)(wt_data & 0xFFFF);
                
                // Cập nhật Threshold từ 16-bit cao (Thực tế chỉ chốt ở nhịp cuối, nhưng cứ đọc ra)
                uint16_t cur_thresh = (uint16_t)((wt_data >> 16) & 0x7FFF);
                uint8_t  polarity   = (uint8_t)((wt_data >> 31) & 0x1);
                
                // Tính Popcount cho 16 cặp (Act XNOR Weight)
                int pop_cnt = xnor_popcount(act_rd_data, wt_16b);

                // Tích lũy (acc_reg)
                // acc_clr = 1 tại pixel_cnt == 1 (Nhịp hợp lệ đầu tiên của mỗi node)
                if (pixel_cnt == 1) {
                    acc_reg = pop_cnt; // Nạp đè
                } else {
                    acc_reg += pop_cnt; // Cộng dồn
                }
                
                // Cập nhật lại Thresh để dùng lúc so sánh
                final_thresh = cur_thresh;
            }

            // ----------------------------------------------------
            // 3. CHỐT KẾT QUẢ VÀ IN LOG (is_acc_done)
            // ----------------------------------------------------
            if (pixel_cnt == 36) { // is_acc_done = 1
                // Tính toán Bit Out (So sánh Acc với Threshold)
                // (Ở đây bỏ qua logic Polarity cho đơn giản, chỉ mô phỏng Acc >= Thresh)
                out_bit = (acc_reg >= final_thresh) ? 1 : 0;

                // Testbench bắt tại nhịp valid_out (trễ 1 nhịp so với is_acc_done)
                // nhưng trong C ta có thể in ngay lập tức
                printf("# Node [%2d] | Popcount: %3d/576 | Threshold: %3d -> Bit Out: %d\n", 
                       out_ch, acc_reg, final_thresh, out_bit);
            }

            // ----------------------------------------------------
            // 4. CHUYỂN TRẠNG THÁI
            // ----------------------------------------------------
            if (pixel_cnt == 37) {
                // pixel_cnt sẽ bị reset về 0 bởi vòng lặp for bên ngoài (out_ch++)
                // Không làm gì thêm, chuẩn bị sang Node tiếp theo
            }
        } // Hết 38 Clock của 1 Node
    } // Hết 64 Node
    printf("# >>> HOÀN TẤT LAYER 3 <<<\n");
}