#include "gpio_protocol.h"

volatile bool flag_fpga_done = false;

/*****************************************************************************
* Function		: FPGA_Sync_GPIO_Init
* Description	: Khởi tạo GPIO cho FPGA bằng thanh ghi (Register) SONiX
*****************************************************************************/
void FPGA_Sync_GPIO_Init(void) {
    // --- Thiết lập cho chân P3.13 (FPGA DONE) ---
    // 1. Set Mode Input (Xóa bit 13 của thanh ghi MODE về 0)
    SN_GPIO3->MODE &= ~(1 << FPGA_DONE_PIN);

    // 2. Cấu hình ngắt: Cạnh lên (Rising Edge)
    SN_GPIO3->IS  &= ~(1 << FPGA_DONE_PIN); // 0: Edge Sensitive (Cạnh)
    SN_GPIO3->IBS &= ~(1 << FPGA_DONE_PIN); // 0: Single Edge (Một cạnh)
    SN_GPIO3->IEV |=  (1 << FPGA_DONE_PIN); // 1: Rising Edge (Cạnh lên)

    // 3. Xóa cờ ngắt cũ và bật ngắt cho P3.13
    SN_GPIO3->IC  =  (1 << FPGA_DONE_PIN);  // Ghi 1 để xóa (Clear)
    SN_GPIO3->IE  |= (1 << FPGA_DONE_PIN);  // Bật ngắt (Enable)

    // --- Thiết lập cho chân P3.12 (FPGA RESULT) ---
    // 1. Set Mode Input (Xóa bit 12 của thanh ghi MODE về 0)
    SN_GPIO3->MODE &= ~(1 << FPGA_RESULT_PIN);
    
    // 2. Bật Pull-up (Trở kéo lên) cho P3.12 
    // (Thanh ghi CFG dùng 2 bit cho mỗi chân, chân 12 tương ứng bit 24-25. Giá trị Pull-up là b'10 = 2)
    SN_GPIO3->CFG = (SN_GPIO3->CFG & ~(3 << (FPGA_RESULT_PIN * 2))) | (2 << (FPGA_RESULT_PIN * 2));
    
    // Bật ngắt ngầm cho Port 3 trên hệ thống NVIC của ARM Cortex
    NVIC_EnableIRQ(P3_IRQn);
}

/*****************************************************************************
* Function		: FPGA_Read_Result
* Description	: Đọc giá trị mức logic từ chân P3.12
*****************************************************************************/
uint8_t FPGA_Read_Result(void) {
    // Đọc trực tiếp từ thanh ghi DATA của Port 3
    if (SN_GPIO3->DATA & (1 << FPGA_RESULT_PIN)) {
        return 1; // Mắt mở
    }
    return 0;     // Mắt nhắm
}

/*****************************************************************************
* Function		: P3_IRQHandler
* Description	: Trình phục vụ ngắt Port 3
*****************************************************************************/
void P3_IRQHandler(void) {
    // Kiểm tra cờ ngắt của P3.13 trong thanh ghi RIS (Raw Interrupt Status)
    if (SN_GPIO3->RIS & (1 << FPGA_DONE_PIN)) {
        
        flag_fpga_done = true;
        
        // Xóa cờ ngắt bằng cách ghi 1 vào thanh ghi IC (Interrupt Clear)
        SN_GPIO3->IC = (1 << FPGA_DONE_PIN);
    }
}