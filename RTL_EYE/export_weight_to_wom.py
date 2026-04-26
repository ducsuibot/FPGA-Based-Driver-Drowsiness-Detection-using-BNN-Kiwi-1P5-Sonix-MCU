# Tên file: convert_for_gowin.py

def create_gowin_mi_file(input_file, output_mi_file):
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"Lỗi: Không tìm thấy file {input_file}")
        return

    # Lọc dữ liệu: Chỉ lấy các dòng hex, viết HOA toàn bộ cho chuẩn Gowin
    clean_hex_lines = []
    for line in lines:
        l = line.strip()
        # Bỏ qua dòng trống hoặc chứa thẻ như [source]
        if l and not l.startswith('['):
            clean_hex_lines.append(l.upper())

    # Ghi ra định dạng .mi cho Gowin IP Core
    with open(output_mi_file, 'w', encoding='utf-8') as f:
        for hex_val in clean_hex_lines:
            f.write(hex_val + "\n")

    print(f"Đã tạo thành công file: {output_mi_file}")
    print(f"Hãy dùng file này để chọn trong mục 'Initialization' của IP Core Generator.")

if __name__ == "__main__":
    create_gowin_mi_file("bnn_weights_sim.txt", "bnn_weights_gowin.mi")