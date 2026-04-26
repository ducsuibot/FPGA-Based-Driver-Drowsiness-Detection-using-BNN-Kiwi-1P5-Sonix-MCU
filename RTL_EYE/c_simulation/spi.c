#include <stdint.h>
#include <stdbool.h>

#define TOTAL_BYTES 72

// ========================================================
// 1. CÁC BIẾN TRẠNG THÁI (Tương đương thanh ghi Flip-Flop)
// ========================================================
uint8_t  shift_reg  = 0;    // Thanh ghi dịch 8-bit
uint8_t  bit_cnt    = 0;    // Đếm số bit (0 -> 7)
uint8_t  rx_addr    = 0;    // Địa chỉ lưu RAM
uint8_t  rx_data    = 0;    // Dữ liệu 1 byte hoàn chỉnh
bool     rx_valid   = false;// Cờ báo nhận xong 1 byte
bool     frame_done = false;// Cờ báo nhận xong toàn bộ ảnh

uint8_t  act_ram[TOTAL_BYTES]; // BRAM trên FPGA

// ========================================================
// 2. GIAI ĐOẠN A: BẮT ĐẦU KHUNG TRUYỀN
// Tương đương: if (spi_cs_fall)
// ========================================================
void on_spi_cs_fall() {
    // MCU kéo CS xuống 0 -> Reset hệ thống để đón ảnh mới
    bit_cnt    = 0;
    rx_addr    = 0;
    frame_done = false;
    rx_valid   = false;
}

// ========================================================
// 3. GIAI ĐOẠN B: DỊCH VÀ CHỐT BIT
// Tương đương: else if (spi_cs_active) -> if (spi_clk_rise)
// ========================================================
void on_spi_clk_rise(bool spi_mosi_bit) {
    // 3.1 Dịch trái thanh ghi và nạp bit MOSI vào cuối (MSB First)
    // Tương đương: shift_reg <= {shift_reg[6:0], mosi_sync[1]};
    shift_reg = (shift_reg << 1) | (spi_mosi_bit & 0x01);
    
    // 3.2 Kiểm tra xem đã đủ 8 bit chưa
    if (bit_cnt == 7) {
        rx_valid = true;
        rx_data  = shift_reg;
        
        // --- Xử lý ghi RAM (Mô phỏng độ trễ 1 clock của phần cứng) ---
        act_ram[rx_addr] = rx_data; // act_we = 1
        rx_addr++;                  // Tăng địa chỉ chờ byte tiếp theo
        
        bit_cnt = 0; // Reset đếm bit để đón byte mới
    } else {
        rx_valid = false;
        bit_cnt++;
    }
}

// ========================================================
// 4. GIAI ĐOẠN C: KẾT THÚC KHUNG TRUYỀN
// Tương đương: else if (spi_cs_rise)
// ========================================================
void on_spi_cs_rise() {
    // MCU kéo CS lên 1 -> Kiểm tra xem đã nhận đủ 72 bytes chưa.
    // Lưu ý: Ở bản C, rx_addr đã tự tăng lên 72 ở byte cuối cùng, 
    // nên ta so sánh >= 72 (Khác với phần cứng so sánh >= 71 để bù trễ clock).
    if (rx_addr >= TOTAL_BYTES) {
        frame_done = true; 
        
        // Ngay sau lệnh này, khối control_fsm sẽ thoát S_IDLE và chạy CONV1
    }
}