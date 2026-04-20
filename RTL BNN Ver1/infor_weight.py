# Tên file: decode_weights_exact.py
import re

def decode_bnn_weights(input_file, output_report):
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"Lỗi: Không tìm thấy file {input_file}")
        return

    valid_lines = [l.strip().upper() for l in lines if l.strip() and not l.startswith('[')]
    hex_pattern = re.compile(r'^[0-9A-Fa-f]{8}$')

    with open(output_report, 'w', encoding='utf-8') as f:
        f.write("========== BÁO CÁO GIẢI MÃ CHÍNH XÁC BNN WEIGHTS ==========\n")
        f.write(f"Tổng số từ: {len(valid_lines)} words (Chuẩn: 16 + 256 + 2304 + 4 = 2580)\n")
        f.write("===========================================================\n\n")

        for i, line in enumerate(valid_lines):
            if not hex_pattern.match(line):
                f.write(f"Addr {i:<4} | {line} -> LỖI ĐỊNH DẠNG\n")
                continue

            val = int(line, 16)

            # ==========================================
            # 1. LAYER CONV1 (Addr 0 -> 15)
            # ==========================================
            if i < 16:
                if i == 0: f.write("\n--- LỚP CONV1 (16 Filters x 9-bit) ---\n")
                polarity   = (val >> 31) & 0x1
                threshold  = (val >> 16) & 0x7FFF
                weight_9b  = val & 0x01FF  # Chỉ lấy 9 bit cuối
                w_bin      = format(weight_9b, '09b')
                f.write(f"Addr {i:<4} | Hex: {line} | Flt: {i:<2} | Pol: {polarity} | Thresh: {threshold:<5} | W_9b: {w_bin}\n")

            # ==========================================
            # 2. LAYER CONV2 (Addr 16 -> 271)
            # ==========================================
            elif i < 272:
                if i == 16: f.write("\n--- LỚP CONV2 (16 Filters x 16 Channels, Dual Threshold) ---\n")
                idx = i - 16
                flt = idx // 16
                ch  = idx % 16
                weight_9b = val & 0x01FF
                w_bin = format(weight_9b, '09b')

                if ch == 15: # Kênh cuối chứa thông tin Threshold
                    neg_th   = (val >> 24) & 0xFF
                    pos_th   = (val >> 16) & 0xFF
                    polarity = (val >> 15) & 0x1
                    f.write(f"Addr {i:<4} | Hex: {line} | Flt: {flt:<2} Ch: {ch:<2} | Pol: {polarity} | Pos_Th: {pos_th:<3} | Neg_Th: {neg_th:<3} | W_9b: {w_bin}\n")
                else: # Kênh 0-14 không chứa Threshold
                    f.write(f"Addr {i:<4} | Hex: {line} | Flt: {flt:<2} Ch: {ch:<2} | (No Threshold)                | W_9b: {w_bin}\n")

            # ==========================================
            # 3. LAYER FC1 (Addr 272 -> 2575)
            # ==========================================
            elif i < 2576:
                if i == 272: f.write("\n--- LỚP FC1 (64 Nodes x 36 Chunks x 16-bit) ---\n")
                idx = i - 272
                node  = idx // 36
                chunk = idx % 36
                polarity   = (val >> 31) & 0x1
                threshold  = (val >> 16) & 0x7FFF
                weight_16b = val & 0xFFFF
                w_bin      = format(weight_16b, '016b')
                f.write(f"Addr {i:<4} | Hex: {line} | Node:{node:<2} Chunk:{chunk:<2} | Pol: {polarity} | Thresh: {threshold:<3} | W_16b: {w_bin}\n")

            # ==========================================
            # 4. LAYER FC2 (Addr 2576 -> 2579)
            # ==========================================
            else:
                if i == 2576: f.write("\n--- LỚP FC2 (1 Node x 4 Chunks x 16-bit) ---\n")
                chunk = i - 2576
                polarity   = (val >> 31) & 0x1
                threshold  = (val >> 16) & 0x7FFF
                weight_16b = val & 0xFFFF
                w_bin      = format(weight_16b, '016b')
                f.write(f"Addr {i:<4} | Hex: {line} | Chunk:{chunk:<2}         | Pol: {polarity} | Thresh: {threshold:<3} | W_16b: {w_bin}\n")

    print(f"Hoàn tất giải mã! Đã lưu báo cáo tại {output_report}")

if __name__ == "__main__":
    decode_bnn_weights("bnn_weights_sim.txt", "bnn_decoded_report.txt")