/*****************************************************************************
* PROJECT: DRIVER DROWSINESS DETECTION & DIGITAL CLOCK
* Tích hợp thuật toán PERCLOS (còi ẩn) và Đồng hồ LED 7 đoạn có nút chỉnh
*****************************************************************************/

/*_____ I N C L U D E S ____________________________________________________*/
#include <SN32F400.h>
#include <SN32F400_Def.h>
#include <stdbool.h>
#include "..\Driver\GPIO.h"
#include "..\Driver\WDT.h"
#include "..\Driver\Utility.h"
#include "..\Module\Segment.h"
#include "gpio_protocol.h"
#include "perclos.h"

/*_____ D E C L A R A T I O N S ____________________________________________*/
void PFPA_Init(void);
void NotPinOut_GPIO_init(void);
void System_Peripheral_Init(void);
void Button_Clock_Init(void);
void Scan_Clock_Buttons(void);

/*_____ V A R I A B L E S  (ĐỒNG HỒ) _______________________________________*/
uint8_t hours = 23;   // Giờ mặc định khi khởi động
uint8_t minutes = 0;  // Phút
uint8_t seconds = 0;  // Giây
uint16_t ms_tick = 0; // Đếm mili-giây

#ifndef SN32F407
    #error Please install SONiX.SN32F4_DFP.0.0.18.pack or version >= 0.0.18
#endif
#define PKG SN32F407                

/*_____ F U N C T I O N S __________________________________________________*/

int main(void)
{
    SystemInit();
    SystemCoreClockUpdate(); 

    PFPA_Init(); 
    NotPinOut_GPIO_init();

    System_Peripheral_Init();
    
    // Bật Reset và Watchdog Timer
    SN_SYS0->EXRSTCTRL_b.RESETDIS = 0;
    WDT_Init(); 

    while (1)
    {
        __WDT_FEED_VALUE;

        // =========================================================
        // NHIỆM VỤ 1: CHẠY NGẦM THUẬT TOÁN CẢNH BÁO MẮT
        // =========================================================
        if (flag_fpga_done) 
        {
            flag_fpga_done = false;
            uint8_t eye_status = FPGA_Read_Result();
            
            Update_PERCLOS_And_Alarm(eye_status);
        }

        // =========================================================
        // NHIỆM VỤ 2: ĐỒNG HỒ THỜI GIAN THỰC (RTC)
        // =========================================================
        ms_tick++; 
        if (ms_tick >= 1000) {  
            ms_tick = 0;
            seconds++;
            
            if (seconds >= 60) {
                seconds = 0;
                minutes++;
                
                if (minutes >= 60) {
                    minutes = 0;
                    hours++;
                    
                    if (hours >= 24) {
                        hours = 0;
                    }
                }
            }
        }

        // =========================================================
        // NHIỆM VỤ 3: QUÉT NÚT BẤM (ĐỂ CHỈNH GIỜ/PHÚT)
        // =========================================================
        Scan_Clock_Buttons();

        // =========================================================
        // NHIỆM VỤ 4: HIỂN THỊ RA LED 7 ĐOẠN
        // =========================================================
        uint16_t display_time = (hours * 100) + minutes; 
        Digital_DisplayDEC(display_time);
        Digital_Scan(); 
        UT_DelayNx10us(100); 
    }
}

/*****************************************************************************
* Khởi tạo các ngoại vi hệ thống
*****************************************************************************/
void System_Peripheral_Init(void)
{
    // Đã xóa thanh ghi AHBCLKCTRL sai lệch
    // Dùng hàm khởi tạo GPIO chuẩn của project để thiết lập các chân LED 7 đoạn
    GPIO_Init(); 

    FPGA_Sync_GPIO_Init(); // Khởi tạo chân giao tiếp FPGA (P3.13, P3.12)
    Buzzer_Init();         // Khởi tạo còi báo động (P3.0)
    Button_Clock_Init();   // Khởi tạo 2 nút nhấn (P2.0, P2.1)
}

/*****************************************************************************
* Khởi tạo Nút bấm SW3 (P2.4) và SW4 (P2.5) dùng chung ROW0 (P1.4)
*****************************************************************************/
void Button_Clock_Init(void) {
    // 1. Cấu hình P1.4 (ROW0) làm Output và xuất mức LOW (0) để làm Mass giả
    SN_GPIO1->MODE |= (1 << 4);  // Bật bit 4 lên 1 -> Output
    SN_GPIO1->BCLR = (1 << 4);   // Kéo P1.4 xuống mức 0

    // 2. Cấu hình P2.4 (COL0) và P2.5 (COL1) làm Input
    SN_GPIO2->MODE &= ~((1 << 4) | (1 << 5)); // Xóa bit 4 và 5 về 0 -> Input
    
    // Trên mạch đã có trở kéo lên 4.7K, nhưng ta có thể bật thêm Pull-up nội bộ cho an toàn
    // CFG cần giá trị b'10 = 2. P2.4 (bit 8-9), P2.5 (bit 10-11)
    SN_GPIO2->CFG = (SN_GPIO2->CFG & ~(0x0F << 8)) | (0x0A << 8); 
}

/*****************************************************************************
* Quét nút bấm chỉnh thời gian (SW3 và SW4)
*****************************************************************************/
void Scan_Clock_Buttons(void) {
    
    // Nút SW3: Chỉnh GIỜ (Đọc chân P2.4)
    if ((SN_GPIO2->DATA & (1 << 4)) == 0) {
        UT_DelayNx10us(2000); // Chống dội phím (Debounce 20ms)
        if ((SN_GPIO2->DATA & (1 << 4)) == 0) {
            hours++;
            if (hours >= 24) hours = 0;
            
            // Chờ nhả nút (tránh việc nhấn giữ số chạy liên tục)
            while ((SN_GPIO2->DATA & (1 << 4)) == 0) {
                Digital_Scan(); // Vẫn quét LED để màn không bị chớp
                UT_DelayNx10us(100);
            }
        }
    }

    // Nút SW4: Chỉnh PHÚT (Đọc chân P2.5)
    if ((SN_GPIO2->DATA & (1 << 5)) == 0) {
        UT_DelayNx10us(2000); // Chống dội phím
        if ((SN_GPIO2->DATA & (1 << 5)) == 0) {
            minutes++;
            if (minutes >= 60) minutes = 0;
            seconds = 0; // Chỉnh phút thì reset giây cho chuẩn xác
            
            // Chờ nhả nút
            while ((SN_GPIO2->DATA & (1 << 5)) == 0) {
                Digital_Scan(); 
                UT_DelayNx10us(100);
            }
        }
    }
}

/*****************************************************************************
* Các hàm hệ thống mặc định
*****************************************************************************/
void NotPinOut_GPIO_init(void)
{
#if (PKG == SN32F407)
    // Cấu hình chân không dùng cho gói SN32F407
    SN_GPIO2->CFG = 0xAAAAAAAA; 
#elif (PKG == SN32F405)
    SN_GPIO0->CFG = 0x00A008AA;
    SN_GPIO1->CFG = 0x000000AA;
    SN_GPIO3->CFG = 0x0002AAAA;
#endif
}

void HardFault_Handler(void)
{
    NVIC_SystemReset();
}