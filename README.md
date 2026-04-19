# FPGA-Based-Driver-Drowsiness-Detection-using-BNN-Kiwi-1P5-Sonix-MCU
This project implements a real-time driver drowsiness detection system using a Binary Neural Network (BNN) on a Kiwi GW1N-1P5 FPGA. A Sonix MCU captures and preprocesses images using Otsu thresholding for adaptive binarization. The processed data is sent to the FPGA for low-latency, hardware-accelerated inference with optimized resource usage.

## 👥 Team & Task Allocation

The project is divided into two primary technical tracks: Pre-processing (MCU) and Hardware Acceleration (FPGA).

| Functional Group | Members | Key Responsibilities |
| :--- | :--- | :--- |
| **MCU & Pre-processing** | **Hoàng Văn Thái (Leader)**<br>**Vũ Văn Việt** | • Develop UART communication to receive image data from PC.<br>• Implement **OTSU Algorithm** for adaptive image thresholding.<br>• Build the **SPI Master** protocol to stream processed data to the FPGA. |
| **FPGA & BNN Inference** | **Nguyễn Minh Đức**<br>**Quang Bách** | • Design the **Binary Neural Network (BNN)** architecture on FPGA Kiwi 1P5.<br>• Develop optimized **Line Buffers** and Datapath (XNOR-Popcount).<br>• Design FSM-based controllers and verify bit-accurate inference. |

---

## 🛠 Technical Stack

### **AI Model Training (Python)**
* **Python**: Primary language for model development and training.
* **PyTorch / TensorFlow**: Used to design and train the BNN architecture.
* **Larq / Brevitas**: Specialized libraries for Quantization-Aware Training (QAT) to produce 1-bit weights.
* **OpenCV & NumPy**: Used for dataset preparation, augmentation, and C-model verification.

### **Hardware Implementation**
* **FPGA (Gowin GW1N-1P5)**: Hardware acceleration target using Verilog HDL for low-latency inference.
* **MCU (Sonix)**: Embedded C-based control for image capturing and SPI data streaming.
* **Communication**: SPI (MCU-FPGA), UART (PC-MCU).

### **Development Tools**
* **Gowin EDA**: Synthesis and Place & Route for the Kiwi 1P5 board.
* **QuestaSim / ModelSim**: RTL simulation and bit-by-bit verification against the C-model.
* **Sonix IDE**: Embedded C development for the Sonix MCU series.
