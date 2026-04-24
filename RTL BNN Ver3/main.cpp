#include <Arduino.h>
#include <SPI.h>

// 1. ĐỊNH NGHĨA CHÂN SPI
#define CS_PIN PA4

// 2. KHAI BÁO 8 CHÂN LED (Từ Bit 7 xuống Bit 0)
// Tôi chọn các chân từ PB15 rải dài xuống PB8 vì trên con BluePill 
// các chân này nằm sát nhau thành một dải rất dễ cắm dây test-board.
const int LED_PINS[8] = {
    PB15, // Index 0 -> Bit 7 (Cờ Busy)
    PB14, // Index 1 -> Bit 6 (Popcount MSB)
    PB13, // Index 2 -> Bit 5 (Popcount)
    PB12, // Index 3 -> Bit 4 (Popcount)
    PB11, // Index 4 -> Bit 3 (Popcount)
    PB10, // Index 5 -> Bit 2 (Popcount)
    PB9,  // Index 6 -> Bit 1 (Popcount LSB)
    PB8   // Index 7 -> Bit 0 (Kết quả Mở/Nhắm)
};

// Mảng ảnh test
uint8_t test_img[72] = {
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0xC4, 0xC6, 0x00, 0xC1, 0xFF, 0x80, 0x0E, 0x01, 0xC0,
    0xFB, 0x00, 0x00, 0x1C, 0x0F, 0xF8, 0x12, 0x0F, 0xF4,
    0x2E, 0x00, 0xF8, 0x0C, 0x02, 0x7C, 0x0D, 0x06, 0x7C,
    0x0F, 0x05, 0xFC, 0x47, 0xBF, 0xFE, 0xE7, 0xFF, 0xFE,
    0xE7, 0xFF, 0xDE, 0xE7, 0xFF, 0xFF, 0x77, 0xFF, 0xFF,
    0x73, 0xFF, 0xFF, 0x79, 0xFF, 0xFF, 0x7C, 0xFF, 0xFE,
    0xFF, 0x3F, 0xFE, 0xFF, 0xFF, 0xFE, 0xFF, 0xFF, 0xFE
};

// Hàm hỗ trợ xuất 1 byte ra 8 bóng LED
void hien_thi_8_led(uint8_t byte_val) {
    for (int i = 0; i < 8; i++) {
        // Dịch phải (7-i) bit để lấy từng bit từ MSB đến LSB, sau đó AND với 1
        bool bit_state = (byte_val >> (7 - i)) & 0x01;
        digitalWrite(LED_PINS[i], bit_state ? HIGH : LOW);
    }
}

void setup() {
    Serial.begin(115200);
    
    // Khởi tạo chân CS
    pinMode(CS_PIN, OUTPUT);
    digitalWrite(CS_PIN, HIGH); 

    // Khởi tạo 8 chân LED và tắt hết ban đầu
    for (int i = 0; i < 8; i++) {
        pinMode(LED_PINS[i], OUTPUT);
        digitalWrite(LED_PINS[i], LOW);
    }

    SPI.begin();
    SPI.beginTransaction(SPISettings(2000000, MSBFIRST, SPI_MODE0));
    
    Serial.println("STM32 da san sang!");

    // =========================================================
    // TRUYỀN 1 ẢNH DUY NHẤT LÚC KHỞI ĐỘNG
    // =========================================================
    Serial.println("Dang ban 72 bytes anh xuong FPGA...");
    digitalWrite(CS_PIN, LOW);
    for(int i = 0; i < 72; i++) {
        SPI.transfer(test_img[i]);
    }
    digitalWrite(CS_PIN, HIGH);
    Serial.println("Ban xong! Bat dau qua trinh lang nghe MISO...\n");
}

void loop() {
    uint8_t status_byte;
    bool is_busy = true;

    // --- BƯỚC 1: HỎI THĂM TRẠNG THÁI FPGA ---
    while (is_busy) {
        digitalWrite(CS_PIN, LOW);   
        status_byte = SPI.transfer(0x00); 
        digitalWrite(CS_PIN, HIGH);  

        // CẬP NHẬT TRỰC TIẾP RA 8 LED (Real-time MISO)
        hien_thi_8_led(status_byte);

        // Trích xuất bit 7 để kiểm tra xem FPGA đã rảnh chưa
        is_busy = (status_byte & 0x80) != 0; 

        if (is_busy) {
            delay(5); // Chờ 5ms rồi hỏi lại
        }
    }

    // --- BƯỚC 2: FPGA ĐÃ TÍNH XONG ---
    // Vì không có ảnh mới được gửi, vòng lặp loop() sẽ chạy lại,
    // biến is_busy sẽ lập tức là false, và nó lại in kết quả ra đây.
    
    Serial.print("FPGA da ranh! Raw MISO (Ban doc tren LED): 0b");
    for(int i = 7; i >= 0; i--) {
        Serial.print((status_byte >> i) & 1);
    }
    Serial.println();

    // Chờ 2 giây rồi mới đọc lại trạng thái để Terminal không bị trôi quá nhanh.
    // Trong lúc này, 8 LED vẫn sáng ổn định báo cáo Popcount và Result.
    delay(2000); 
}