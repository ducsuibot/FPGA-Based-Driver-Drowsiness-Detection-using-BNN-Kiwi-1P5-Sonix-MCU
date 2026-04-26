#include <stdint.h>
#include <stdbool.h>

// =========================================================================
// 1. KHAI BÁO BỘ NHỚ VÀ THANH GHI PHẦN CỨNG (HARDWARE REGISTERS)
// =========================================================================
uint16_t act_ram[2048];       // BRAM chứa ảnh Input và các Feature Map
uint32_t weight_rom[3000];    // ROM chứa trọng số và ngưỡng (đã gộp 32-bit)

// Thanh ghi dịch Line Buffer cho CONV1 (Chiều dài 24 tương ứng với ảnh 24x24)
bool lb0[24] = {0}; 
bool lb1[24] = {0};

// 9 thanh ghi tạo thành cửa sổ quét 3x3
bool w00=0, w01=0, w02=0;
bool w10=0, w11=0, w12=0;
bool w20=0, w21=0, w22=0;

// =========================================================================
// 2. CÁC HÀM MÔ PHỎNG MẠCH TỔ HỢP (COMBINATIONAL LOGIC)
// =========================================================================

// Mạch bóc tách 1 bit pixel từ ô nhớ 16-bit của BRAM (is_img_read = 1)
bool extract_1bit_pixel(int pixel_index) {
    int fetch_addr = pixel_index >> 3; // Lấy nguyên (chia 8) để tìm ô nhớ
    int bit_idx    = pixel_index & 7;  // Lấy dư (chia 8) để tìm vị trí bit
    
    uint16_t raw_data = act_ram[fetch_addr];
    // Trích xuất bit theo chuẩn MSB First của mạch
    return (raw_data >> (7 - bit_idx)) & 0x01; 
}

// Mạch dịch cửa sổ 3x3 và Line Buffer (Kích hoạt khi shift_en = 1)
void shift_window_conv1(bool new_pixel) {
    // Dịch các hàng trong cửa sổ 3x3
    w20 = w21; w21 = w22; w22 = new_pixel; // Hàng dưới cùng nạp pixel mới
    w10 = w11; w11 = w12; w12 = lb0[23];   // Hàng giữa nạp dữ liệu rơi ra từ Line Buffer 0
    w00 = w01; w01 = w02; w02 = lb1[23];   // Hàng trên nạp dữ liệu rơi ra từ Line Buffer 1

    // Dịch các Line Buffer
    for (int i = 23; i > 0; i--) {
        lb0[i] = lb0[i-1];
        lb1[i] = lb1[i-1];
    }
    lb0[0] = new_pixel;
    lb1[0] = lb0[23]; // Dữ liệu tràn từ lb0 chảy xuống lb1
}

// Mạch đếm số bit 1 (Popcount) cho 9 bit
int popcount9(uint16_t val) {
    int count = 0;
    for(int i = 0; i < 9; i++) {
        count += (val >> i) & 1;
    }
    return count;
}

// =========================================================================
// 3. HÀM CHÍNH: QUÁ TRÌNH THỰC THI CONV1
// =========================================================================
void run_conv1_process() {
    int act_wr_addr = 72;  // Bắt đầu ghi Output Feature Map từ địa chỉ 72
    int rd_addr_cnt = 0;   // Biến đếm chỉ số pixel đang đọc
    int wt_addr = 0;       // Con trỏ ROM trọng số

    // ---------------------------------------------------------------------
    // GIAI ĐOẠN 1: PRE-READ (NẠP ĐÀ LINE BUFFER)
    // FSM State: C1_PRE_ADDR -> C1_PRE_SHIFT
    // ---------------------------------------------------------------------
    // Nạp trước 24 pixel của hàng đầu tiên vào Line Buffer để tạo khung 3x3
    for (int pixel_cnt = 0; pixel_cnt < 24; pixel_cnt++) {
        bool px = extract_1bit_pixel(rd_addr_cnt++); 
        shift_window_conv1(px);
    }

    // ---------------------------------------------------------------------
    // GIAI ĐOẠN 2 & 3: QUÉT ẢNH VÀ TÍNH TOÁN (COMPUTE & STORE)
    // FSM State: C1_ADDR -> C1_CALC
    // ---------------------------------------------------------------------
    for (int pad_y = 0; pad_y < 24; pad_y++) {
        for (int pad_x = 0; pad_x < 24; pad_x++) {
            
            // --- BƯỚC 2.1: LOAD LƯỚI ẢNH (LOOK-AHEAD READ) ---
            // Đọc pixel tiếp theo chuẩn bị cho nhịp trượt cửa sổ
            // Mạch Verilog: act_rd_addr <= pad_y*24 + pad_x + 25;
            bool new_px = 0;
            if (rd_addr_cnt < 576) { 
                new_px = extract_1bit_pixel(rd_addr_cnt++);
            }
            shift_window_conv1(new_px);

            // --- BƯỚC 2.2: MẠCH ZERO-PADDING ---
            // Nếu tọa độ chạm lề, ép tín hiệu điểm ảnh đó về 0 (Mạch MUX tổ hợp)
            bool pad_top    = (pad_y == 0);
            bool pad_bottom = (pad_y == 23);
            bool pad_left   = (pad_x == 0);
            bool pad_right  = (pad_x == 23);
            
            uint16_t win_1b = 0;
            win_1b |= ((pad_top || pad_left)     ? 0 : w00) << 8;
            win_1b |= ((pad_top)                 ? 0 : w01) << 7;
            win_1b |= ((pad_top || pad_right)    ? 0 : w02) << 6;
            win_1b |= ((pad_left)                ? 0 : w10) << 5;
            win_1b |= (                                w11) << 4; // Tâm cửa sổ không bao giờ ra ngoài
            win_1b |= ((pad_right)               ? 0 : w12) << 3;
            win_1b |= ((pad_bottom || pad_left)  ? 0 : w20) << 2;
            win_1b |= ((pad_bottom)              ? 0 : w21) << 1;
            win_1b |= ((pad_bottom || pad_right) ? 0 : w22) << 0;

            // --- BƯỚC 3: COMPUTE VÀ ĐÓNG GÓI BITS (STORE) ---
            // Ảnh nhị phân chỉ có 1 kênh (in_ch=1). Mạch xoay vòng qua 16 bộ lọc (out_ch)
            uint16_t bg_buffer = 0; // Thanh ghi đóng gói 16 bit
            
            for (int out_ch = 0; out_ch < 16; out_ch++) {
                
                // 1. Đọc ROM (Lấy Trọng số 9-bit và Ngưỡng 15-bit + 1-bit Polarity)
                uint32_t flash_word = weight_rom[wt_addr++]; 
                uint16_t wgt_data   = flash_word & 0xFFFF;       
                uint16_t thresh_reg = (flash_word >> 16) & 0xFFFF; 
                
                // 2. Compute: Tính XNOR và Popcount trên 9 bit
                uint16_t xnor_res = ~(win_1b ^ wgt_data);
                uint16_t masked_x = xnor_res & 0x01FF; // Mask bỏ các bit rác ở trên
                int pop_cnt = popcount9(masked_x);
                
                // Ở CONV1, không cần cộng dồn qua nhiều Input Channel vì ảnh đen trắng chỉ có độ sâu = 1.
                // Do đó acc_reg chính là pop_cnt của nhịp này.
                int acc_reg = pop_cnt; 
                
                // 3. Hàm kích hoạt Batch Norm & Binarization
                bool polarity = (thresh_reg >> 15) & 1;
                int threshold_val = thresh_reg & 0x7FFF;
                
                bool datapath_out; // Kết quả 1-bit của nơ-ron
                if (polarity) datapath_out = (acc_reg >= threshold_val);
                else          datapath_out = (acc_reg <= threshold_val);
                
                // 4. Bit Packing (Gom bit)
                // Đẩy bit kết quả vào đầu thanh ghi dịch (Tương đương Verilog: {datapath_out, bg_buffer[15:1]})
                bg_buffer = (datapath_out << 15) | (bg_buffer >> 1);
            }

            // --- BƯỚC 4: LƯU VÀO RAM (ACT_WE = 1) ---
            // Cứ hết vòng lặp 16 filters (đã gom đủ 16 bit), ta mới ghi vào RAM 1 lần
            act_ram[act_wr_addr] = bg_buffer; 
            act_wr_addr++; 
            
        } // Nhích cửa sổ sang phải 1 pixel
    } // Xuống hàng ngang tiếp theo

    // Kết thúc vòng lặp, Feature Map của CONV1 đã nằm gọn trong BRAM từ địa chỉ 72 đến 647.
}