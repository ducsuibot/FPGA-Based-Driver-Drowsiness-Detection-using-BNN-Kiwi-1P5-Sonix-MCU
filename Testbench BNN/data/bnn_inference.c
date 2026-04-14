#include <stdio.h>
#include <stdlib.h>

// --- KHAI BÁO BỘ NHỚ TRỌNG SỐ & NGƯỠNG ---
int w_conv1[16][9], w_conv2[16][144], w_fc1[64][576], w_fc2[64];
int bn1_p[16], bn1_t[16];
int bn2_p[16], bn2_tpos[16], bn2_tneg[16];
int bn3_p[64], bn3_t[64];
int bn4_p, bn4_t;

// --- HÀM HỖ TRỢ ---
void read_mem(const char *fname, int *arr, int bits) {
    FILE *f = fopen(fname, "r");
    if (!f) exit(1);
    char c; int count = 0;
    while ((c = fgetc(f)) != EOF && count < bits)
        if (c == '0' || c == '1') arr[count++] = c - '0';
    fclose(f);
}

int get_pixel(int *img, int ch, int r, int c, int size) {
    // Nếu tọa độ vượt ra khỏi kích thước ảnh -> Trả về thẳng số 0 (Zero Padding)
    if (r < 0 || r >= size || c < 0 || c >= size) {
        return 0; 
    }
    
    // Nếu tọa độ nằm trong ảnh -> Truy xuất giá trị bình thường
    return img[ch * size * size + r * size + c];
}

int main() {
    // 1. NẠP DỮ LIỆU TỪ Ổ CỨNG
    read_mem("fpga_weights/conv1_weight.mem", (int*)w_conv1, 144);
    read_mem("fpga_weights/conv2_weight.mem", (int*)w_conv2, 2304);
    read_mem("fpga_weights/fc1_weight.mem", (int*)w_fc1, 36864);
    read_mem("fpga_weights/fc2_weight.mem", w_fc2, 64);

    FILE *f;
    f = fopen("fpga_weights/bn1_thresholds.txt", "r"); for(int i=0; i<16; i++) fscanf(f, "%d %d", &bn1_p[i], &bn1_t[i]); fclose(f);
    f = fopen("fpga_weights/bn2_thresholds.txt", "r"); for(int i=0; i<16; i++) fscanf(f, "%d %d %d", &bn2_p[i], &bn2_tpos[i], &bn2_tneg[i]); fclose(f);
    f = fopen("fpga_weights/bn3_thresholds.txt", "r"); for(int i=0; i<64; i++) fscanf(f, "%d %d", &bn3_p[i], &bn3_t[i]); fclose(f);
    f = fopen("fpga_weights/bn4_thresholds.txt", "r"); fscanf(f, "%d %d", &bn4_p, &bn4_t); fclose(f);

    int img_in[1][24][24];
    read_mem("input_image.txt", (int*)img_in, 576);

    // --- IN HEADER LOG ---
    printf("# ==================================================\n");
    printf("#  BAO CAO TINH TOAN BIT-BY-BIT TREN FPGA (MOI NHAT)\n");
    printf("# ==================================================\n#\n");
    printf("# STM32: Bat dau gui anh (72 bytes) qua SPI...\n");
    printf("# STM32: Da gui xong! He thong FPGA bat dau xu ly mang AI...\n#\n");

    // 2. LAYER 1: CONV1 + MAXPOOL 1
    int conv1[16][24][24], pool1[16][12][12];
    for (int f = 0; f < 16; f++) {
        for (int r = 0; r < 24; r++) {
            for (int c = 0; c < 24; c++) {
                int pop = 0, w_idx = 0;
                for (int i = -1; i <= 1; i++)
                    for (int j = -1; j <= 1; j++)
                        if (get_pixel((int*)img_in, 0, r+i, c+j, 24) == w_conv1[f][w_idx++]) pop++;
                
                conv1[f][r][c] = (bn1_p[f] == 1) ? (pop >= bn1_t[f]) : (pop <= bn1_t[f]);

                // --- IN LOG CONV1 ---
                if (f == 0 && r < 2 && c < 2) {
                    if (r == 0 && c == 0) printf("\n# >>> LAYER 1: CONV1 (Trich xuat 2x2 Pixel dau tien) <<<\n");
                    printf("# Pixel [%d,%d] | Popcount: %d/9 | Threshold: %d -> Bit Out: %d\n", 
                           r, c, pop, bn1_t[f], conv1[f][r][c]);
                }
            }
        }
        // MaxPool 2x2 (Tối ưu bằng phép toán Bitwise OR cho ảnh nhị phân)
        for (int r = 0; r < 12; r++)
            for (int c = 0; c < 12; c++)
                pool1[f][r][c] = conv1[f][r*2][c*2] | conv1[f][r*2+1][c*2] | conv1[f][r*2][c*2+1] | conv1[f][r*2+1][c*2+1];
    }

    // 3. LAYER 2: CONV2 (Dual Threshold) + MAXPOOL 2
    int conv2[16][12][12], pool2[16][6][6];
    for (int f = 0; f < 16; f++) {
        for (int r = 0; r < 12; r++) {
            for (int c = 0; c < 12; c++) {
                int pop = 0, w_idx = 0;
                for (int ch = 0; ch < 16; ch++)
                    for (int i = -1; i <= 1; i++)
                        for (int j = -1; j <= 1; j++)
                            if (get_pixel((int*)pool1, ch, r+i, c+j, 12) == w_conv2[f][w_idx++]) pop++;
                
                int thresh = (pool1[f][r][c] == 1) ? bn2_tpos[f] : bn2_tneg[f];
                conv2[f][r][c] = (bn2_p[f] == 1) ? (pop >= thresh) : (pop <= thresh);

                // --- IN LOG CONV2 ---
                if (f == 0 && r < 2 && c < 2) {
                    if (r == 0 && c == 0) printf("\n# >>> LAYER 2: CONV2 (Trich xuat 2x2 Pixel dau tien) <<<\n");
                    printf("# Pixel [%d,%d] | Popcount: %d/144 | Dung Threshold: %d -> Bit Out: %d\n", 
                           r, c, pop, thresh, conv2[f][r][c]);
                }
            }
        }
        // MaxPool 2x2
        for (int r = 0; r < 6; r++)
            for (int c = 0; c < 6; c++)
                pool2[f][r][c] = conv2[f][r*2][c*2] | conv2[f][r*2+1][c*2] | conv2[f][r*2][c*2+1] | conv2[f][r*2+1][c*2+1];
    }

    // 4. LAYER 3: FC1
    int fc1[64];
    for (int n = 0; n < 64; n++) {
        int pop = 0, w_idx = 0;
        for (int ch = 0; ch < 16; ch++)
            for (int r = 0; r < 6; r++)
                for (int c = 0; c < 6; c++)
                    if (pool2[ch][r][c] == w_fc1[n][w_idx++]) pop++;
                    
        fc1[n] = (bn3_p[n] == 1) ? (pop >= bn3_t[n]) : (pop <= bn3_t[n]);

        // --- IN LOG FC1 ---
        if (n == 0) printf("\n# >>> LAYER 3: FULLY CONNECTED 1 (Toan bo 64 Node) <<<\n");
        printf("# Node [%d] | Popcount: %d/576 | Threshold: %d -> Bit Out: %d\n", 
               n, pop, bn3_t[n], fc1[n]);
    }

    // 5. LAYER 4: FC2 (KẾT QUẢ CUỐI CÙNG)
    int pop_final = 0;
    for (int i = 0; i < 64; i++) {
        if (fc1[i] == w_fc2[i]) pop_final++;
    }
    
    int result = (bn4_p == 1) ? (pop_final >= bn4_t) : (pop_final <= bn4_t);

    // --- IN LOG FC2 & KẾT LUẬN ---
    printf("\n# >>> LAYER 4: FULLY CONNECTED 2 (Lop chot ha) <<<\n");
    printf("# FINAL DECISION | Popcount: %d/64 | Threshold: %d -> RESULT: %d\n#\n", pop_final, bn4_t, result);
    printf("# ========================================\n");
    printf("# HOAN TAT SUY LUAN FPGA!\n");
    if (result == 1) {
        printf("# => KET LUAN CUA PHAN CUNG: MO MAT (1)\n");
    } else {
        printf("# => KET LUAN CUA PHAN CUNG: NHAM MAT (0)\n");
    }
    printf("# ========================================\n");

    return 0;
}