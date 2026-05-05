#include "perclos.h"
#include <SN32F400.h>

// --- ĐỊNH NGHĨA CHÂN LOA NGOÀI ---
// Đang sử dụng chân P3.11 theo yêu cầu
#define SPEAKER_PORT    SN_GPIO3
#define SPEAKER_PIN     11

// --- BIẾN TOÀN CỤC ---
// Chỉ cần 1 biến đếm số frame nhắm mắt liên tiếp
uint16_t consecutive_closed_count = 0;    

// =========================================================
// HÀM KHỞI TẠO GPIO CHO LOA NGOÀI (Tại P3.11)
// =========================================================
void Buzzer_Init(void) {
    // 1. Set chân P3.11 thành Output (Bật bit 11 trong thanh ghi MODE lên 1)
    SPEAKER_PORT->MODE |= (1 << SPEAKER_PIN);
    
    // 2. Xuất mức Low ban đầu để tắt loa (Dùng thanh ghi BCLR - Bit Clear)
    SPEAKER_PORT->BCLR = (1 << SPEAKER_PIN);
}

// =========================================================
// HÀM CẬP NHẬT VÀ QUYẾT ĐỊNH
// =========================================================
void Update_PERCLOS_And_Alarm(uint8_t current_frame_is_closed) {
    
    // BƯỚC 1: XỬ LÝ ĐẾM NHẮM MẮT
    if (current_frame_is_closed == 0) {
        // Nếu nhắm (0) -> Tăng biến đếm
        consecutive_closed_count++; 
    } else {
        // Nếu mở (1) -> Reset đếm về 0
        consecutive_closed_count = 0;
    }

    // BƯỚC 2: KIỂM TRA NGƯỠNG BÁO ĐỘNG
    if (consecutive_closed_count >= MICROSLEEP_THRESHOLD) {
        SPEAKER_PORT->BSET = (1 << SPEAKER_PIN); 
    } else {
        SPEAKER_PORT->BCLR = (1 << SPEAKER_PIN);
    }
}