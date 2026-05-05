#ifndef __PERCLOS_H__
#define __PERCLOS_H__

#include <stdint.h>
#include <stdbool.h>

// --- ĐIỀU KIỆN: NHẮM MẮT LIÊN TỤC ---
// Nếu nhắm tịt mắt LIÊN TỤC >= 20 frames -> BÁO ĐỘNG NGAY
#define MICROSLEEP_THRESHOLD 20 

// --- KHAI BÁO HÀM ---
void Buzzer_Init(void);
void Update_PERCLOS_And_Alarm(uint8_t current_frame_is_closed);

#endif // __PERCLOS_H__