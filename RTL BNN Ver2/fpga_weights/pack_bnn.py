import struct
import os

def parse_thresholds(filename, is_dual=False):
    thres_list = []
    with open(filename, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if not parts: continue
            sign = int(parts[0])
            if is_dual:
                t1, t2 = int(parts[1]), int(parts[2])
                val = ((t2 & 0xFF) << 24) | ((t1 & 0xFF) << 16) | ((sign & 0x1) << 15)
                thres_list.append(val)
            else:
                t = int(parts[1])
                thres_list.append((sign << 15) | (t & 0x7FFF))
    return thres_list

def pack_weights():
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))

    # Đọc Thresholds
    bn1 = parse_thresholds(os.path.join(BASE_DIR, 'bn1_thresholds.txt'))
    bn2 = parse_thresholds(os.path.join(BASE_DIR, 'bn2_thresholds.txt'), is_dual=True)
    bn3 = parse_thresholds(os.path.join(BASE_DIR, 'bn3_thresholds.txt'))
    bn4 = parse_thresholds(os.path.join(BASE_DIR, 'bn4_thresholds.txt'))

    words_32bit = []

    # 1. Xử lý CONV1 (16 filter x 9 bit)
    with open(os.path.join(BASE_DIR, 'conv1_weight.txt'), 'r') as f:
        for i, line in enumerate([l.strip() for l in f if l.strip()]):
            w_val = int("1111111" + line, 2)
            words_32bit.append((bn1[i] << 16) | w_val)

    # 2. Xử lý CONV2 (16 filter x 16 kênh x 9 bit)
    with open(os.path.join(BASE_DIR, 'conv2_weight.txt'), 'r') as f:
        for i, line in enumerate([l.strip() for l in f if l.strip()]):
            for ch in range(16):
                w_9bit = int(line[ch*9 : (ch+1)*9], 2) 
                if ch == 15:
                    words_32bit.append(bn2[i] | w_9bit)
                else:
                    w_val = int("1111111" + line[ch*9 : (ch+1)*9], 2)
                    words_32bit.append(w_val & 0xFFFFFFFF)

    # 3. Xử lý FC1 (BẢN MỚI: 32 neuron x 576 bit)
    with open(os.path.join(BASE_DIR, 'fc1_weight.txt'), 'r') as f:
        for i, line in enumerate([l.strip() for l in f if l.strip()]):
            for chunk_idx in range(36):
                chunk = line[chunk_idx*16 : (chunk_idx+1)*16]
                w_val = int(chunk[::-1], 2)
                t_val = bn3[i] 
                words_32bit.append((t_val << 16) | w_val)

    # 4. Xử lý FC2 (BẢN MỚI: 1 neuron x 32 bit)
    with open(os.path.join(BASE_DIR, 'fc2_weight.txt'), 'r') as f:
        line = f.read().strip()
        # SỬA Ở ĐÂY: range(4) -> range(2) vì 32 bit = 2 chunks x 16 bit
        for chunk_idx in range(2): 
            chunk = line[chunk_idx*16 : (chunk_idx+1)*16]
            w_val = int(chunk[::-1], 2)
            t_val = bn4[0] 
            words_32bit.append((t_val << 16) | w_val)

    # =====================================================================
    # 1. XUẤT FILE CHUẨN INTEL HEX
    # =====================================================================
    hex_path = os.path.join(BASE_DIR, 'bnn_weights.hex')
    with open(hex_path, 'w') as f:
        address = 0
        for i in range(0, len(words_32bit), 4):
            chunk = words_32bit[i:i+4]
            data_bytes = []
            for word in chunk:
                data_bytes.append((word >> 24) & 0xFF) 
                data_bytes.append((word >> 16) & 0xFF) 
                data_bytes.append((word >> 8) & 0xFF)  
                data_bytes.append(word & 0xFF)         

            record_len = len(data_bytes)
            hex_data = "".join(f"{b:02X}" for b in data_bytes)
            
            checksum_sum = record_len + (address >> 8) + (address & 0xFF) + 0 + sum(data_bytes)
            checksum = (~checksum_sum + 1) & 0xFF
            
            f.write(f":{record_len:02X}{address:04X}00{hex_data}{checksum:02X}\n")
            address += record_len
            
        f.write(":00000001FF\n") 
        
    # =====================================================================
    # 2. XUẤT FILE RAW HEX (MÔ PHỎNG)
    # =====================================================================
    sim_path = os.path.join(BASE_DIR, 'bnn_weights_sim.txt')
    with open(sim_path, 'w') as f_sim:
        for word in words_32bit:
            f_sim.write(f"{word:08X}\n")

    print(f"Đã đóng gói {len(words_32bit)} words thành công!")
    print(f" -> File nạp mạch : bnn_weights.hex")
    print(f" -> File mô phỏng : bnn_weights_sim.txt")

if __name__ == '__main__':
    pack_weights()