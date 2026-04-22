# 1. Đọc file trọng số CHW cũ
with open("fc1_weight.txt", "r") as f:
    lines = [l.strip() for l in f if l.strip()]

# 2. Xoay sang HWC và ghi đè
with open("fc1_weight_hwc.txt", "w") as f_out:
    for line in lines:
        new_line = ""
        for p in range(36):         # Lặp qua 36 pixel (H x W)
            for ch in range(16):    # Lặp qua 16 kênh (C)
                # Công thức ánh xạ từ HWC sang CHW
                old_idx = ch * 36 + p
                new_line += line[old_idx]
        f_out.write(new_line + "\n")

print(f"Đã sắp xếp lại trọng số FC1 từ CHW sang HWC cho {len(lines)} node!") # Sẽ in ra 32 node
print("Hãy đổi tên fc1_weight_hwc.txt thành fc1_weight.txt rồi chạy lại các code khác.")