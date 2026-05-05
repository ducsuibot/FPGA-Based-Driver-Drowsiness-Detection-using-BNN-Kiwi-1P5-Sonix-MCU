#ifndef __GPIO_PROTOCOL_H__
#define __GPIO_PROTOCOL_H__

#include <stdint.h>
#include <stdbool.h>
#include <SN32F400.h>

extern volatile bool flag_fpga_done;

#define FPGA_DONE_PIN     13   // Bit 13 tương ứng chân P3.13
#define FPGA_RESULT_PIN   12   // Bit 12 tương ứng chân P3.12

void FPGA_Sync_GPIO_Init(void);
uint8_t FPGA_Read_Result(void);

#endif