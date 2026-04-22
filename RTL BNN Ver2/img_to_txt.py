import cv2
import numpy as np
import os

current_dir = os.path.dirname(os.path.abspath(__file__))
img_path = os.path.join(current_dir, "my_eye.png")

# 1. Tiền xử lý (Giống hệt phần cứng)
img = cv2.imread(img_path, cv2.IMREAD_GRAYSCALE)
img_24x24 = cv2.resize(img, (24, 24), interpolation=cv2.INTER_AREA)
blurred = cv2.GaussianBlur(img_24x24, (3, 3), 0)
_, binary_img = cv2.threshold(blurred, 0, 1, cv2.THRESH_BINARY + cv2.THRESH_OTSU)

# 2. Xuất ra file input_image.txt cho C đọc
out_path = os.path.join(current_dir, "input_image.txt")
with open(out_path, 'w') as f:
    for row in binary_img:
        # Ghi các bit 0 và 1 liền nhau trên 1 dòng
        bit_string = "".join([str(int(b)) for b in row])
        f.write(bit_string + "\n")

print(f"✅ Đã tạo ảnh nhị phân cho C tại: {out_path}")