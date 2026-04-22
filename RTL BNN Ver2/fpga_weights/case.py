import os

def generate_hardcoded_rom(input_file="bnn_weights_sim.txt", output_file="weight_rom_hardcoded.v"):
    """
    Đọc file HEX 32-bit (mỗi dòng 1 word) và sinh ra module ROM Verilog dùng cấu trúc CASE.
    """
    if not os.path.exists(input_file):
        print(f"❌ Lỗi: Không tìm thấy file {input_file} trong thư mục hiện tại.")
        return

    # Đọc dữ liệu từ file sim
    try:
        with open(input_file, 'r') as f:
            lines = [line.strip() for line in f if line.strip()]
    except Exception as e:
        print(f"❌ Lỗi khi đọc file: {e}")
        return

    total_words = len(lines)
    print(f"🔍 Đã đọc được {total_words} words từ {input_file}.")

    # Bắt đầu ghi file Verilog
    try:
        with open(output_file, 'w') as f_out:
            # Header module
            f_out.write("`timescale 1ns / 1ps\n\n")
            f_out.write("module weight_rom (\n")
            f_out.write("    input  wire        clk,\n")
            f_out.write("    input  wire [11:0] addr, \n")
            f_out.write("    output reg  [31:0] data  \n")
            f_out.write(");\n\n")

            # Khối always và case
            f_out.write("    always @(posedge clk) begin\n")
            f_out.write("        case (addr)\n")

            # Ghi từng dòng case
            for addr, hex_val in enumerate(lines):
                # Định dạng: 12'd0: data <= 32'h8005FF17;
                f_out.write(f"            12'd{addr:<4}: data <= 32'h{hex_val};\n")

            # Khối default an toàn (tránh sinh latch)
            f_out.write("            default: data <= 32'h00000000;\n")
            
            # Kết thúc case và module
            f_out.write("        endcase\n")
            f_out.write("    end\n\n")
            f_out.write("endmodule\n")

        print(f"✅ Đã tạo thành công file {output_file} chứa {total_words} case!")
        print("👉 Hãy copy file này thay thế cho module weight_rom cũ trong dự án của bạn.")

    except Exception as e:
        print(f"❌ Lỗi khi ghi file Verilog: {e}")

if __name__ == "__main__":
    generate_hardcoded_rom()