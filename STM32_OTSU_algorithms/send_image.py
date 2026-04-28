# import cv2
# import serial
# import time
# import numpy as np
# import threading
# import subprocess # Thêm thư viện để gọi code C
# import os

# COM_PORT = '/dev/ttyUSB0'
# BAUD_RATE = 115200

# try:
#     ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=2)
#     time.sleep(1)
#     ser.reset_input_buffer()
#     print(f"✅ Đã kết nối {COM_PORT}")
# except Exception as e:
#     print(f"❌ Lỗi mở cổng COM: {e}")
#     exit()

# is_processing = False
# current_debug_panel = np.zeros((480, 300, 3), dtype=np.uint8)
# ai_status_text = "SAN SANG (An 's')"

# # =====================================================================
# # HÀM CHẠY C-MODEL ĐỂ ĐỐI CHIẾU
# # =====================================================================
# def run_c_model_on_pc(bin_img):
#     try:
#         # 1. Ép ảnh nhị phân thành mảng 1D chứa toàn '0' và '1'
#         bin_flat = (bin_img.flatten() > 127).astype(int)
        
#         # 2. Ghi ra file input_image.txt cho code C đọc
#         with open("/home/hiura/Hiura/stm32/test/src/input_image.txt", "w") as f:
#             f.write("".join(map(str, bin_flat)))
        
#         # 3. Gọi file thực thi ./golden_model (Chạy ngầm)
#         if not os.path.exists("/home/hiura/Hiura/stm32/test/src/golden_model"):
#             print("⚠️ Chưa có file ./golden_model. Hãy chạy: gcc golden_model.c -o golden_model")
#             return -1, -1
            
#         # Sửa từ "./golden_model" thành "./src/golden_model" hoặc dùng đường dẫn tuyệt đối
#         result = subprocess.run(["/home/hiura/Hiura/stm32/test/src/golden_model"], capture_output=True, text=True, cwd="/home/hiura/Hiura/stm32/test/src")
#         output = result.stdout
        
#         # 4. Quét log output để bóc tách Popcount và Result cuối cùng
#         pop_c, res_c = -1, -1
#         for line in output.split('\n'):
#             if "FINAL DECISION" in line:
#                 # VD Dòng: # FINAL DECISION | Popcount: 19/32 | Threshold: 14 -> RESULT: 1
#                 part1 = line.split("Popcount: ")[1]
#                 pop_c = int(part1.split("/")[0])
#                 res_c = int(part1.split("RESULT: ")[1])
#         return pop_c, res_c
#     except Exception as e:
#         print(f"⚠️ Lỗi chạy C-Model: {e}")
#         return -1, -1

# # =====================================================================
# # CÁC HÀM XỬ LÝ ẢNH (Giữ nguyên)
# # =====================================================================
# def restore_binary_image_from_hex_lines(hex_lines):
#     try:
#         raw_hex_str = "".join(hex_lines).replace(" ", "")
#         packed_bytes = bytearray.fromhex(raw_hex_str)

#         def unpack_one_eye(packed_eye_bytes):
#             eye_24x24 = np.zeros((24, 24), dtype=np.uint8)
#             for i in range(72):
#                 one_byte = packed_eye_bytes[i]
#                 for bit in range(8):
#                     if (one_byte >> (7 - bit)) & 0x01:
#                         eye_24x24[i // 3, (i % 3) * 8 + bit] = 255
#                     else:
#                         eye_24x24[i // 3, (i % 3) * 8 + bit] = 0
#             return eye_24x24

#         eye_left_24 = unpack_one_eye(packed_bytes[:72])
#         eye_right_24 = unpack_one_eye(packed_bytes[72:])
#         return eye_left_24, eye_right_24
#     except Exception as e:
#         print(f"❌ Lỗi giải nén: {e}")
#         return None, None

# def create_debug_panel(left_gray, left_bin, right_gray, right_bin, th_l, th_r):
#     panel = np.zeros((480, 300, 3), dtype=np.uint8)
#     panel[:] = (30, 30, 30)

#     cv2.putText(panel, "AI EDGE ACCELERATOR", (15, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 2)
#     cv2.putText(panel, "STM32 MCU Status", (15, 55), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (200, 200, 200), 1)
#     cv2.line(panel, (10, 70), (290, 70), (100, 100, 100), 1)

#     def draw_eye_block(gray_img, bin_img, y_start, title, threshold):
#         cv2.putText(panel, f"--- {title} ---", (100, y_start + 15), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)
#         IMG_SIZE = 100
#         gray_big = cv2.resize(gray_img, (IMG_SIZE, IMG_SIZE), interpolation=cv2.INTER_NEAREST)
#         gray_color = cv2.cvtColor(gray_big, cv2.COLOR_GRAY2BGR)
#         bin_big = cv2.resize(bin_img, (IMG_SIZE, IMG_SIZE), interpolation=cv2.INTER_NEAREST)
#         bin_color = cv2.cvtColor(bin_big, cv2.COLOR_GRAY2BGR)

#         panel[y_start + 30 : y_start + 30 + IMG_SIZE, 30 : 30 + IMG_SIZE] = gray_color
#         cv2.putText(panel, "Gray", (65, y_start + 145), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)
#         panel[y_start + 30 : y_start + 30 + IMG_SIZE, 170 : 170 + IMG_SIZE] = bin_color
#         cv2.putText(panel, f"Otsu: {threshold}", (185, y_start + 145), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 165, 255), 1)

#     draw_eye_block(left_gray, left_bin, 80, "MAT TRAI", th_l)
#     cv2.line(panel, (50, 260), (250, 260), (70, 70, 70), 1)
#     draw_eye_block(right_gray, right_bin, 280, "MAT PHAI", th_r)

#     return panel

# # =====================================================================
# # THREAD XỬ LÝ (ĐÃ TÍCH HỢP ĐỐI CHIẾU C-MODEL)
# # =====================================================================
# def ai_worker(left_24, right_24):
#     global is_processing, current_debug_panel, ai_status_text

#     ai_status_text = "DANG GUI STM32..."
#     try:
#         payload = bytearray(left_24.flatten().tolist() + right_24.flatten().tolist())

#         ser.reset_input_buffer()
#         ser.write(bytes([0xAA]))
#         ser.flush()

#         ready = False
#         start_time = time.time()
#         while time.time() - start_time < 2:
#             if ser.in_waiting > 0:
#                 line = ser.readline().decode('utf-8', errors='ignore').strip()
#                 if "READY" in line:
#                     ready = True
#                     break

#         if not ready:
#             print("\n❌ LỖI: STM32 không trả lời.")
#             ai_status_text = "LOI KET NOI!"
#             is_processing = False
#             return

#         ai_status_text = "STM32/FPGA DANG TINH..."
#         chunk_size = 64
#         for i in range(0, len(payload), chunk_size):
#             ser.write(payload[i : i + chunk_size])
#             time.sleep(0.002)
#         ser.flush()

#         capture_hex_lines = []
#         capture_start = False
#         final_thresholds = [127, 127]
        
#         # Biến hứng kết quả từ FPGA
#         l_pop_fpga, l_res_fpga = 0, 0
#         r_pop_fpga, r_res_fpga = 0, 0

#         start_time = time.time()
#         while time.time() - start_time < 5:
#             if ser.in_waiting > 0:
#                 response = ser.readline().decode('utf-8', errors='ignore').strip()
                
#                 # Bắt tín hiệu FPGA gửi từ STM32
#                 if response.startswith("FPGA Trai:"):
#                     try:
#                         l_pop_fpga = int(response.split("Pop=")[1].split(",")[0])
#                         l_res_fpga = int(response.split("Res=")[1])
#                     except: pass
#                     continue
#                 elif response.startswith("FPGA Phai:"):
#                     try:
#                         r_pop_fpga = int(response.split("Pop=")[1].split(",")[0])
#                         r_res_fpga = int(response.split("Res=")[1])
#                     except: pass
#                     continue

#                 if response.startswith("Otsu Trai:"):
#                     final_thresholds[0] = int(response.split(":")[1])
#                 elif response.startswith("Otsu Phai:"):
#                     final_thresholds[1] = int(response.split(":")[1])

#                 if response == "HEX:":
#                     capture_start = True
#                     capture_hex_lines = []
#                     continue

#                 if capture_start and len(response) > 5 and not response.startswith("-"):
#                     capture_hex_lines.append(response)
#                     if len(capture_hex_lines) == 8:
#                         break

#         # KHI ĐÃ CÓ ẢNH VÀ KẾT QUẢ FPGA -> CHẠY C-MODEL VÀ SO SÁNH
#         if len(capture_hex_lines) == 8:
#             left_bin, right_bin = restore_binary_image_from_hex_lines(capture_hex_lines)
#             if left_bin is not None:
#                 current_debug_panel = create_debug_panel(
#                     left_24, left_bin, right_24, right_bin,
#                     final_thresholds[0], final_thresholds[1]
#                 )
                
#                 # Chạy C-Model
#                 l_pop_c, l_res_c = run_c_model_on_pc(left_bin)
#                 r_pop_c, r_res_c = run_c_model_on_pc(right_bin)

#                 # In bảng đối chiếu ra Terminal
#                 print("\n" + "═" * 55)
#                 print("📊 BẢNG ĐỐI CHIẾU KẾT QUẢ (PHẦN CỨNG vs PHẦN MỀM)")
#                 print("═" * 55)
                
#                 match_l = "✅ KHỚP NHAU" if (l_pop_fpga == l_pop_c and l_res_fpga == l_res_c) else "❌ LỆCH DATA"
#                 print(f"👁️ MẮT TRÁI : {match_l}")
#                 print(f"   ▶ FPGA Gowin  : Pop={l_pop_fpga:2d}, Result={l_res_fpga}")
#                 print(f"   ▶ C-Model (PC): Pop={l_pop_c:2d}, Result={l_res_c}")
#                 print("-" * 55)
                
#                 match_r = "✅ KHỚP NHAU" if (r_pop_fpga == r_pop_c and r_res_fpga == r_res_c) else "❌ LỆCH DATA"
#                 print(f"👁️ MẮT PHẢI : {match_r}")
#                 print(f"   ▶ FPGA Gowin  : Pop={r_pop_fpga:2d}, Result={r_res_fpga}")
#                 print(f"   ▶ C-Model (PC): Pop={r_pop_c:2d}, Result={r_res_c}")
#                 print("═" * 55 + "\n")

#                 ai_status_text = "HOAN TAT!"
#         else:
#             ai_status_text = "LOI DATA STM32"
#             print(f"\n⚠️ Bị rớt gói tin HEX.")

#     except Exception as e:
#         print(f"Lỗi Thread: {e}")
#         ai_status_text = "LOI HE THONG"

#     is_processing = False

# # =====================================================================
# # LUỒNG CHÍNH (GUI CAMERA)
# # =====================================================================
# cap = cv2.VideoCapture(0)
# cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
# cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

# DISPLAY_BOX_SIZE = 120
# CENTER_X = 640 // 2
# CENTER_Y = 480 // 2

# lx1, lx2 = CENTER_X - DISPLAY_BOX_SIZE, CENTER_X
# ly1, ly2 = CENTER_Y - (DISPLAY_BOX_SIZE // 2), CENTER_Y + (DISPLAY_BOX_SIZE // 2)

# rx1, rx2 = CENTER_X, CENTER_X + DISPLAY_BOX_SIZE
# ry1, ry2 = CENTER_Y - (DISPLAY_BOX_SIZE // 2), CENTER_Y + (DISPLAY_BOX_SIZE // 2)

# print("\n" + "="*50)
# print("📸 HỆ THỐNG VERIFICATION ĐÃ SẴN SÀNG")
# print("👉 Bấm 's' : Chụp & Đối chiếu FPGA vs C-Model")
# print("👉 Bấm 'q' : Thoát")
# print("="*50)

# while True:
#     ret, frame = cap.read()
#     if not ret: break

#     frame = cv2.flip(frame, 1)
#     gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

#     left_eye_120 = gray[ly1:ly2, lx1:lx2]
#     right_eye_120 = gray[ry1:ry2, rx1:rx2]

#     cv2.rectangle(frame, (lx1, ly1), (lx2, ly2), (0, 255, 0), 2)
#     cv2.rectangle(frame, (rx1, ry1), (rx2, ry2), (0, 255, 0), 2)

#     if is_processing: color = (0, 165, 255) 
#     elif "LOI" in ai_status_text: color = (0, 0, 255) 
#     else: color = (0, 255, 0) 

#     cv2.putText(frame, f"STATUS: {ai_status_text}", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, color, 2)

#     frame_with_debug = cv2.hconcat([frame, current_debug_panel])
#     cv2.imshow("Camera - An 's' de gui AI", frame_with_debug)

#     key = cv2.waitKey(1) & 0xFF
#     if key == ord('q'):
#         break
#     elif key == ord('s'):
#         if not is_processing:
#             is_processing = True
#             left_24 = cv2.resize(left_eye_120, (24, 24), interpolation=cv2.INTER_AREA)
#             right_24 = cv2.resize(right_eye_120, (24, 24), interpolation=cv2.INTER_AREA)

#             thread = threading.Thread(target=ai_worker, args=(left_24, right_24))
#             thread.start()

# cap.release()
# cv2.destroyAllWindows()
# ser.close()



import cv2
import serial
import time
import numpy as np
import threading
import subprocess
import os

# =====================================================================
# CẤU HÌNH HỆ THỐNG
# =====================================================================
COM_PORT = '/dev/ttyUSB0'
BAUD_RATE = 115200

# Trạng thái dùng chung giữa các luồng
is_streaming = False
current_payload = None
ai_status_text = "SAN SANG (An 's')"

# Dữ liệu hiển thị (Thêm 2 mảng lưu ảnh nhị phân l_bin, r_bin)
display_data = {
    "fpga_l_pop": 0, "fpga_l_res": 0, "c_l_pop": 0, "c_l_res": 0, "th_l": 0,
    "fpga_r_pop": 0, "fpga_r_res": 0, "c_r_pop": 0, "c_r_res": 0, "th_r": 0,
    "match_l": "WAIT", "match_r": "WAIT",
    "l_bin": np.zeros((24, 24), dtype=np.uint8),
    "r_bin": np.zeros((24, 24), dtype=np.uint8)
}

try:
    ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=0.1)
    time.sleep(1)
    ser.reset_input_buffer()
    print(f"✅ Đã kết nối {COM_PORT}")
except Exception as e:
    print(f"❌ Lỗi mở cổng COM: {e}"); exit()

# =====================================================================
# HÀM CHẠY C-MODEL VÀ VẼ GIAO DIỆN PHỤ
# =====================================================================
def run_c_model_on_pc(bin_img):
    try:
        bin_flat = (bin_img.flatten() > 127).astype(int)
        with open("/home/hiura/Hiura/stm32/test/src/input_image.txt", "w") as f:
            f.write("".join(map(str, bin_flat)))
            
        result = subprocess.run(["/home/hiura/Hiura/stm32/test/src/golden_model"], capture_output=True, text=True, cwd="/home/hiura/Hiura/stm32/test/src")
        pop_c, res_c = -1, -1
        for line in result.stdout.split('\n'):
            if "FINAL DECISION" in line:
                part1 = line.split("Popcount: ")[1]
                pop_c = int(part1.split("/")[0])
                res_c = int(part1.split("RESULT: ")[1])
        return pop_c, res_c
    except Exception as e:
        return -1, -1

def restore_binary_image_from_hex(hex_lines):
    try:
        raw_hex_str = "".join(hex_lines).replace(" ", "")
        packed_bytes = bytearray.fromhex(raw_hex_str)
        def unpack_one_eye(packed_eye_bytes):
            eye_24x24 = np.zeros((24, 24), dtype=np.uint8)
            for i in range(72):
                one_byte = packed_eye_bytes[i]
                for bit in range(8):
                    if (one_byte >> (7 - bit)) & 0x01:
                        eye_24x24[i // 3, (i % 3) * 8 + bit] = 255
            return eye_24x24
        return unpack_one_eye(packed_bytes[:72]), unpack_one_eye(packed_bytes[72:])
    except:
        return None, None

def create_debug_panel(left_gray, left_bin, right_gray, right_bin, th_l, th_r):
    panel = np.zeros((480, 300, 3), dtype=np.uint8)
    panel[:] = (30, 30, 30)

    cv2.putText(panel, "AI EDGE ACCELERATOR", (15, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 2)
    cv2.putText(panel, "STM32 MCU Status", (15, 55), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (200, 200, 200), 1)
    cv2.line(panel, (10, 70), (290, 70), (100, 100, 100), 1)

    def draw_eye_block(gray_img, bin_img, y_start, title, threshold):
        cv2.putText(panel, f"--- {title} ---", (100, y_start + 15), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1)
        IMG_SIZE = 100
        gray_big = cv2.resize(gray_img, (IMG_SIZE, IMG_SIZE), interpolation=cv2.INTER_NEAREST)
        gray_color = cv2.cvtColor(gray_big, cv2.COLOR_GRAY2BGR)
        bin_big = cv2.resize(bin_img, (IMG_SIZE, IMG_SIZE), interpolation=cv2.INTER_NEAREST)
        bin_color = cv2.cvtColor(bin_big, cv2.COLOR_GRAY2BGR)

        panel[y_start + 30 : y_start + 30 + IMG_SIZE, 30 : 30 + IMG_SIZE] = gray_color
        cv2.putText(panel, "Gray", (65, y_start + 145), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)
        panel[y_start + 30 : y_start + 30 + IMG_SIZE, 170 : 170 + IMG_SIZE] = bin_color
        cv2.putText(panel, f"Otsu: {threshold}", (185, y_start + 145), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 165, 255), 1)

    draw_eye_block(left_gray, left_bin, 80, "MAT TRAI", th_l)
    cv2.line(panel, (50, 260), (250, 260), (70, 70, 70), 1)
    draw_eye_block(right_gray, right_bin, 280, "MAT PHAI", th_r)
    return panel

# =====================================================================
# LUỒNG 1: SENDER (BƠM ẢNH LIÊN TỤC)
# =====================================================================
def stream_sender():
    global is_streaming, current_payload, ai_status_text
    ai_status_text = "CONNECTING..."
    ser.write(bytes([0xAA]))
    
    while is_streaming:
        if ser.in_waiting > 0:
            if "READY" in ser.readline().decode('utf-8', errors='ignore'):
                ai_status_text = "STREAMING ACTIVE"
                break
                
    while is_streaming:
        if current_payload is not None:
            ser.write(current_payload)
            ser.flush()
            time.sleep(0.15) 

# =====================================================================
# LUỒNG 2: RECEIVER (HỨNG LOG, CHẠY C-MODEL, CHECK VERIFY)
# =====================================================================
def stream_receiver():
    global is_streaming, display_data
    capture_hex = False
    hex_buffer = []
    
    while True:
        if ser.in_waiting > 0:
            try:
                line = ser.readline().decode('utf-8', errors='ignore').strip()
                
                if line.startswith("Otsu Trai:"): display_data["th_l"] = int(line.split(":")[1])
                elif line.startswith("Otsu Phai:"): display_data["th_r"] = int(line.split(":")[1])
                
                elif line.startswith("FPGA Trai:"):
                    display_data["fpga_l_pop"] = int(line.split("Pop=")[1].split(",")[0])
                    display_data["fpga_l_res"] = int(line.split("Res=")[1])
                elif line.startswith("FPGA Phai:"):
                    display_data["fpga_r_pop"] = int(line.split("Pop=")[1].split(",")[0])
                    display_data["fpga_r_res"] = int(line.split("Res=")[1])
                
                elif line == "HEX:":
                    capture_hex = True
                    hex_buffer = []
                elif capture_hex and len(line) > 5 and not line.startswith("-"):
                    hex_buffer.append(line)
                    if len(hex_buffer) == 8:
                        capture_hex = False
                        # 1. Dựng lại ảnh nhị phân từ chuỗi HEX
                        left_bin, right_bin = restore_binary_image_from_hex(hex_buffer)
                        if left_bin is not None:
                            # Cập nhật ảnh vào display_data để vẽ GUI
                            display_data["l_bin"] = left_bin
                            display_data["r_bin"] = right_bin
                            
                            # 2. Chạy đối chiếu C-Model
                            display_data["c_l_pop"], display_data["c_l_res"] = run_c_model_on_pc(left_bin)
                            display_data["c_r_pop"], display_data["c_r_res"] = run_c_model_on_pc(right_bin)
                            
                            match_l = "✅ KHỚP NHAU" if (display_data["fpga_l_pop"] == display_data["c_l_pop"] and display_data["fpga_l_res"] == display_data["c_l_res"]) else "❌ LỆCH DATA"
                            match_r = "✅ KHỚP NHAU" if (display_data["fpga_r_pop"] == display_data["c_r_pop"] and display_data["fpga_r_res"] == display_data["c_r_res"]) else "❌ LỆCH DATA"
                            
                            display_data["match_l"] = "OK" if "KHỚP" in match_l else "FAIL"
                            display_data["match_r"] = "OK" if "KHỚP" in match_r else "FAIL"
                            
                            # 3. In bảng ra Terminal
                            print("\n" + "═" * 55)
                            print("📊 BẢNG ĐỐI CHIẾU KẾT QUẢ (PHẦN CỨNG vs PHẦN MỀM)")
                            print("═" * 55)
                            print(f"👁️ MẮT TRÁI : {match_l}")
                            print(f"   ▶ FPGA Gowin  : Pop={display_data['fpga_l_pop']:2d}, Result={display_data['fpga_l_res']}")
                            print(f"   ▶ C-Model (PC): Pop={display_data['c_l_pop']:2d}, Result={display_data['c_l_res']}")
                            print("-" * 55)
                            print(f"👁️ MẮT PHẢI : {match_r}")
                            print(f"   ▶ FPGA Gowin  : Pop={display_data['fpga_r_pop']:2d}, Result={display_data['fpga_r_res']}")
                            print(f"   ▶ C-Model (PC): Pop={display_data['c_r_pop']:2d}, Result={display_data['c_r_res']}")
                            print("═" * 55)
            except: pass
        time.sleep(0.001)

threading.Thread(target=stream_receiver, daemon=True).start()

# =====================================================================
# LUỒNG CHÍNH: GIAO DIỆN CAMERA MƯỢT MÀ
# =====================================================================
cap = cv2.VideoCapture(0)
cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

print("\n" + "="*50)
print("🚀 HỆ THỐNG PIPELINE VERIFICATION ĐÃ SẴN SÀNG")
print("👉 Bấm 's' : Bật/Tắt chế độ Real-time Streaming")
print("👉 Bấm 'q' : Thoát")
print("="*50)

while True:
    ret, frame = cap.read()
    if not ret: break
    frame = cv2.flip(frame, 1)
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

    left_eye_120 = gray[240-60:240+60, 320-120:320]
    right_eye_120 = gray[240-60:240+60, 320:320+120]
    
    left_24 = cv2.resize(left_eye_120, (24, 24), interpolation=cv2.INTER_AREA)
    right_24 = cv2.resize(right_eye_120, (24, 24), interpolation=cv2.INTER_AREA)

    if is_streaming:
        current_payload = bytearray(left_24.flatten().tolist() + right_24.flatten().tolist())
        color_st = (0, 255, 0)
    else:
        color_st = (0, 0, 255)
        ai_status_text = "STREAMING OFF"

    cv2.rectangle(frame, (200, 180), (320, 300), (0, 255, 0), 2)
    cv2.rectangle(frame, (320, 180), (440, 300), (0, 255, 0), 2)

    cv2.putText(frame, f"STATUS: {ai_status_text}", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, color_st, 2)
    
    cv2.putText(frame, f"TRAI  [Otsu:{display_data['th_l']}] - FPGA:{display_data['fpga_l_pop']} C:{display_data['c_l_pop']} -> {display_data['match_l']}", (10, 60), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 255), 2)
    cv2.putText(frame, f"PHAI  [Otsu:{display_data['th_r']}] - FPGA:{display_data['fpga_r_pop']} C:{display_data['c_r_pop']} -> {display_data['match_r']}", (10, 85), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 255), 2)

    # Nối cái bảng Debug vào bên phải khung hình Camera
    debug_panel = create_debug_panel(left_24, display_data["l_bin"], right_24, display_data["r_bin"], display_data["th_l"], display_data["th_r"])
    frame_with_debug = cv2.hconcat([frame, debug_panel])

    cv2.imshow("HUST Driver Drowsiness - Pipeline Verification", frame_with_debug)

    key = cv2.waitKey(1) & 0xFF
    if key == ord('q'):
        is_streaming = False
        break
    elif key == ord('s'):
        is_streaming = not is_streaming
        if is_streaming:
            threading.Thread(target=stream_sender, daemon=True).start()

cap.release()
cv2.destroyAllWindows()
ser.close()