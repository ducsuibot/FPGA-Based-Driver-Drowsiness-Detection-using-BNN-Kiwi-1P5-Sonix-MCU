// #include <Arduino.h>
// #include <SPI.h>

// #define TOTAL_RX        1152
// #define TOTAL_TX        144
// #define EYE_SIZE        576
// #define PACKED_SIZE     72

// // Cấu hình chân SPI (Sử dụng SPI1 mặc định của Bluepill)
// #define SPI_CS_PIN      PA4  // Chân Chip Select
// // SCK  = PA5
// // MISO = PA6
// // MOSI = PA7

// uint8_t rx_buffer[TOTAL_RX];
// uint8_t tx_buffer[TOTAL_TX];
// int rx_index = 0;
// bool is_receiving = false; 

// // ==========================================
// // 1. OTSU & ÉP NGƯỠNG
// // ==========================================
// uint8_t Otsu_Threshold(uint8_t* img_data) {
//     int hist[256] = {0};
//     for (int i = 0; i < EYE_SIZE; i++) hist[img_data[i]]++;

//     int sum = 0;
//     for (int i = 0; i < 256; i++) sum += i * hist[i];

//     int sumB = 0, wB = 0, wF = 0;
//     uint32_t varMax = 0;
//     uint8_t threshold = 127;

//     for (int t = 0; t < 256; t++) {
//         wB += hist[t];               
//         if (wB == 0) continue;
//         wF = EYE_SIZE - wB;      
//         if (wF == 0) break;

//         sumB += (t * hist[t]);
//         int mB = sumB / wB;          
//         int mF = (sum - sumB) / wF;  

//         int diff = mB - mF;
//         uint32_t varBetween = (uint32_t)wB * wF * diff * diff;

//         if (varBetween > varMax) {
//             varMax = varBetween;
//             threshold = t;
//         }
//     }

//     if (threshold > 130) threshold -= 30;
//     else if (threshold < 75) threshold += 20;

//     return threshold;
// }

// // ==========================================
// // 2. NHỊ PHÂN HÓA & GÓI BIT 
// // ==========================================
// void Binarize_And_Pack(uint8_t* img_data, uint8_t* packed_data, uint8_t threshold) {
//     for (int i = 0; i < PACKED_SIZE; i++) {
//         packed_data[i] = 0x00; 
//         for (int bit = 0; bit < 8; bit++) {
//             int px_idx = i * 8 + bit;
//             if (img_data[px_idx] > threshold) {
//                 packed_data[i] |= (1 << (7 - bit)); 
//             }
//         }
//     }
// }

// // ==========================================
// // 3. HÀM GIAO TIẾP VỚI FPGA QUA SPI
// // ==========================================
// bool send_to_fpga_and_wait(uint8_t* payload_72b, uint8_t &popcount, uint8_t &result) {
//     SPI.beginTransaction(SPISettings(4000000, MSBFIRST, SPI_MODE0)); // Tốc độ 4MHz
    
//     // BƯỚC 1: Kéo CS xuống, nhồi 72 bytes vào MOSI
//     digitalWrite(SPI_CS_PIN, LOW);
//     for(int i = 0; i < PACKED_SIZE; i++) {
//         SPI.transfer(payload_72b[i]);
//     }
//     digitalWrite(SPI_CS_PIN, HIGH); // Kéo lên để kích hoạt frame_done trên FPGA

//     // BƯỚC 2: POLLING hỏi thăm cờ BUSY
//     unsigned long start_time = millis();
//     while (millis() - start_time < 2000) { // Timeout 2 giây
//         delay(1); // Cho FPGA thở 1 xíu
        
//         // Kéo CS xuống, gửi 1 byte rác (0x00) để lấy MISO về
//         digitalWrite(SPI_CS_PIN, LOW);
//         uint8_t miso_byte = SPI.transfer(0x00);
//         digitalWrite(SPI_CS_PIN, HIGH);

//         // Bóc tách dữ liệu theo format {busy_in, pop_in[5:0], result_in}
//         uint8_t busy = (miso_byte >> 7) & 0x01;
//         popcount     = (miso_byte >> 1) & 0x3F;
//         result       = miso_byte & 0x01;

//         if (busy == 0) {
//             SPI.endTransaction();
//             return true; // FPGA đã tính xong!
//         }
//     }
    
//     SPI.endTransaction();
//     return false; // Quá thời gian (Lỗi kết nối FPGA)
// }

// // ==========================================
// // SETUP & LOOP 
// // ==========================================
// void setup() {
//     Serial1.begin(115200); 
    
//     // Cấu hình SPI
//     pinMode(SPI_CS_PIN, OUTPUT);
//     digitalWrite(SPI_CS_PIN, HIGH); // Mặc định CS mức cao (Không chọn chip)
//     SPI.begin();
    
//     delay(1000);
// }

// void loop() {
//     if (Serial1.available() > 0) {
//         uint8_t incoming_byte = Serial1.read();

//         if (!is_receiving) {
//             if (incoming_byte == 0xAA) {
//                 is_receiving = true;
//                 rx_index = 0;
//                 Serial1.println("READY"); 
//             }
//         } 
//         else {
//             rx_buffer[rx_index++] = incoming_byte;

//             if (rx_index >= TOTAL_RX) {
//                 is_receiving = false; 

//                 uint8_t l_pop = 0, l_res = 0;
//                 uint8_t r_pop = 0, r_res = 0;

//                 // --------------------------------------------------
//                 // XỬ LÝ MẮT TRÁI
//                 // --------------------------------------------------
//                 uint8_t th_left = Otsu_Threshold(&rx_buffer[0]);
//                 Binarize_And_Pack(&rx_buffer[0], &tx_buffer[0], th_left);
//                 bool fpga_l_ok = send_to_fpga_and_wait(&tx_buffer[0], l_pop, l_res);

//                 // --------------------------------------------------
//                 // XỬ LÝ MẮT PHẢI
//                 // --------------------------------------------------
//                 uint8_t th_right = Otsu_Threshold(&rx_buffer[EYE_SIZE]);
//                 Binarize_And_Pack(&rx_buffer[EYE_SIZE], &tx_buffer[PACKED_SIZE], th_right);
//                 bool fpga_r_ok = send_to_fpga_and_wait(&tx_buffer[PACKED_SIZE], r_pop, r_res);

//                 // --------------------------------------------------
//                 // TRẢ KẾT QUẢ VỀ PC
//                 // --------------------------------------------------
//                 Serial1.println("DONE");
//                 Serial1.print("Otsu Trai: "); Serial1.println(th_left);
//                 Serial1.print("Otsu Phai: "); Serial1.println(th_right);
                
//                 // In thêm kết quả FPGA lên cho Python biết
//                 Serial1.print("FPGA Trai: "); Serial1.print(fpga_l_ok ? "OK" : "ERR"); Serial1.print(", Pop="); Serial1.print(l_pop); Serial1.print(", Res="); Serial1.println(l_res);
//                 Serial1.print("FPGA Phai: "); Serial1.print(fpga_r_ok ? "OK" : "ERR"); Serial1.print(", Pop="); Serial1.print(r_pop); Serial1.print(", Res="); Serial1.println(r_res);
                
//                 Serial1.println("HEX:");
//                 for (int i = 0; i < TOTAL_TX; i++) {
//                     if (tx_buffer[i] < 0x10) Serial1.print("0");
//                     Serial1.print(tx_buffer[i], HEX);
//                     Serial1.print(" ");
//                     if ((i + 1) % 18 == 0) Serial1.println(); 
//                 }
//                 Serial1.println("----------------------------------------");
//             }
//         }
//     }
// }



#include <Arduino.h>
#include <SPI.h>

#define TOTAL_RX        1152
#define TOTAL_TX        144
#define EYE_SIZE        576
#define PACKED_SIZE     72

// Cấu hình chân SPI
#define SPI_CS_PIN      PA4
// SCK=PA5, MISO=PA6, MOSI=PA7

// ==========================================
// DOUBLE BUFFERING (PING-PONG)
// ==========================================
uint8_t buffer_A[TOTAL_RX];
uint8_t buffer_B[TOTAL_RX];
uint8_t tx_buffer[TOTAL_TX];

uint8_t *rx_ptr = buffer_A;      // Con trỏ đang hứng data từ PC
uint8_t *process_ptr = NULL;     // Con trỏ đang được mang đi tính toán
int rx_index = 0;
bool is_receiving = false; 
bool data_ready = false;         // Cờ báo hiệu có 1 frame đã sẵn sàng

// ==========================================
// 1. OTSU & ÉP NGƯỠNG
// ==========================================
uint8_t Otsu_Threshold(uint8_t* img_data) {
    int hist[256] = {0};
    for (int i = 0; i < EYE_SIZE; i++) hist[img_data[i]]++;

    int sum = 0;
    for (int i = 0; i < 256; i++) sum += i * hist[i];

    int sumB = 0, wB = 0, wF = 0;
    uint32_t varMax = 0;
    uint8_t threshold = 127;

    for (int t = 0; t < 256; t++) {
        wB += hist[t];               
        if (wB == 0) continue;
        wF = EYE_SIZE - wB;      
        if (wF == 0) break;
        sumB += (t * hist[t]);
        int mB = sumB / wB;          
        int mF = (sum - sumB) / wF;  
        int diff = mB - mF;
        uint32_t varBetween = (uint32_t)wB * wF * diff * diff;
        if (varBetween > varMax) {
            varMax = varBetween;
            threshold = t;
        }
    }
    if (threshold > 130) threshold -= 30;
    else if (threshold < 75) threshold += 20;
    return threshold;
}

// ==========================================
// 2. NHỊ PHÂN HÓA & GÓI BIT 
// ==========================================
void Binarize_And_Pack(uint8_t* img_data, uint8_t* packed_data, uint8_t threshold) {
    for (int i = 0; i < PACKED_SIZE; i++) {
        packed_data[i] = 0x00; 
        for (int bit = 0; bit < 8; bit++) {
            int px_idx = i * 8 + bit;
            if (img_data[px_idx] > threshold) {
                packed_data[i] |= (1 << (7 - bit)); 
            }
        }
    }
}

// ==========================================
// 3. HÀM GIAO TIẾP VỚI FPGA QUA SPI
// ==========================================
bool send_to_fpga_and_wait(uint8_t* payload_72b, uint8_t &popcount, uint8_t &result) {
    SPI.beginTransaction(SPISettings(4000000, MSBFIRST, SPI_MODE0)); 
    
    // BƯỚC 1: Kéo CS xuống, nhồi 72 bytes vào MOSI
    digitalWrite(SPI_CS_PIN, LOW);
    for(int i = 0; i < PACKED_SIZE; i++) {
        SPI.transfer(payload_72b[i]);
    }
    digitalWrite(SPI_CS_PIN, HIGH); 

    // BƯỚC 2: POLLING hỏi thăm cờ BUSY
    unsigned long start_time = millis();
    while (millis() - start_time < 2000) { 
        delay(1); 
        digitalWrite(SPI_CS_PIN, LOW);
        uint8_t miso_byte = SPI.transfer(0x00);
        digitalWrite(SPI_CS_PIN, HIGH);

        uint8_t busy = (miso_byte >> 7) & 0x01;
        popcount     = (miso_byte >> 1) & 0x3F;
        result       = miso_byte & 0x01;

        if (busy == 0) {
            SPI.endTransaction();
            return true; 
        }
    }
    SPI.endTransaction();
    return false; 
}

// ==========================================
// SETUP & LOOP 
// ==========================================
void setup() {
    Serial1.begin(115200); 
    pinMode(SPI_CS_PIN, OUTPUT);
    digitalWrite(SPI_CS_PIN, HIGH); 
    SPI.begin();
    delay(1000);
}

void loop() {
    // --------------------------------------------------
    // STAGE 1: NHẬN DỮ LIỆU NON-BLOCKING (Nhanh như chớp)
    // --------------------------------------------------
    while (Serial1.available() > 0) {
        uint8_t incoming_byte = Serial1.read();

        if (!is_receiving) {
            if (incoming_byte == 0xAA) {
                is_receiving = true;
                rx_index = 0;
                Serial1.println("READY"); 
            }
        } 
        else {
            rx_ptr[rx_index++] = incoming_byte;

            if (rx_index >= TOTAL_RX) {
                // HOÁN ĐỔI BUFFER ĐỂ TIẾP TỤC HỨNG DATA KHÔNG NGỪNG
                process_ptr = rx_ptr;
                rx_ptr = (rx_ptr == buffer_A) ? buffer_B : buffer_A;
                rx_index = 0;
                data_ready = true; // Phất cờ cho Stage 2
            }
        }
    }

    // --------------------------------------------------
    // STAGE 2 & 3: XỬ LÝ & TRẢ KẾT QUẢ ĐỐI CHIẾU
    // --------------------------------------------------
    if (data_ready) {
        data_ready = false; // Hạ cờ

        uint8_t l_pop = 0, l_res = 0;
        uint8_t r_pop = 0, r_res = 0;

        uint8_t th_left = Otsu_Threshold(&process_ptr[0]);
        Binarize_And_Pack(&process_ptr[0], &tx_buffer[0], th_left);
        bool fpga_l_ok = send_to_fpga_and_wait(&tx_buffer[0], l_pop, l_res);

        uint8_t th_right = Otsu_Threshold(&process_ptr[EYE_SIZE]);
        Binarize_And_Pack(&process_ptr[EYE_SIZE], &tx_buffer[PACKED_SIZE], th_right);
        bool fpga_r_ok = send_to_fpga_and_wait(&tx_buffer[PACKED_SIZE], r_pop, r_res);

        // In ĐẦY ĐỦ format để Python quét C-Model
        Serial1.println("DONE");
        Serial1.print("Otsu Trai: "); Serial1.println(th_left);
        Serial1.print("Otsu Phai: "); Serial1.println(th_right);
        
        Serial1.print("FPGA Trai: "); Serial1.print(fpga_l_ok ? "OK" : "ERR"); Serial1.print(", Pop="); Serial1.print(l_pop); Serial1.print(", Res="); Serial1.println(l_res);
        Serial1.print("FPGA Phai: "); Serial1.print(fpga_r_ok ? "OK" : "ERR"); Serial1.print(", Pop="); Serial1.print(r_pop); Serial1.print(", Res="); Serial1.println(r_res);
        
        Serial1.println("HEX:");
        for (int i = 0; i < TOTAL_TX; i++) {
            if (tx_buffer[i] < 0x10) Serial1.print("0");
            Serial1.print(tx_buffer[i], HEX);
            Serial1.print(" ");
            if ((i + 1) % 18 == 0) Serial1.println(); 
        }
        Serial1.println("----------------------------------------");
    }
}