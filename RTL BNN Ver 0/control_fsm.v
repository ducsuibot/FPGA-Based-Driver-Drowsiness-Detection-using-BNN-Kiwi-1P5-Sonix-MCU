`timescale 1ns / 1ps

module control_fsm (
    input  wire clk, rst_n, frame_done, valid_out_fb, datapath_out,
    input  wire [31:0] wt_data, 
    input  wire [15:0] center_pixel, 
    input  wire [15:0] act_rd_data, // Input phải là wire
    
    output reg [11:0] wt_addr, 
    output reg [10:0] act_rd_addr, act_wr_addr,
    
    output wire act_we,             // Dùng wire
    output wire [15:0] act_wr_data, // Dùng wire
    
    output reg shift_en, is_conv2, is_fc, is_img_read,
    output reg [4:0] pad_x, pad_y, in_ch,
    output reg valid_in, acc_clr, is_acc_done,
    output wire [15:0] thresh_val,
    output reg result, done          
);

    // --- Khai báo các thanh ghi trung gian ---
    reg [15:0] fc_buffer;   // Thanh ghi dịch để nén 64 bit thành 4 word
    reg        fc_we;       // Tín hiệu ghi riêng cho lớp FC
    reg [15:0] fc_wr_data;  // Dữ liệu ghi riêng cho lớp FC
    // FIX 1: Thêm trạng thái SHIFT cho CONV1 và CONV2
    localparam S_IDLE=0, S_PR1_A=1, S_PR1_S=2, S_PR1_C=3, S_CV1_A=4, S_CV1_S=5, S_CV1_C=6, S_WAIT=7, S_POOL1=8;
    localparam S_PR2_A=9, S_PR2_S=10, S_PR2_C=11, S_CV2_A=12, S_CV2_S=13, S_CV2_C=14, S_POOL2=15, S_FC1=16, S_FC2=17, S_DONE=18;
    localparam S_CV1_SHIFT=19, S_CV2_SHIFT=20;

    reg [4:0] state, next_state_save;
    reg [9:0] pixel_cnt; 
    reg [5:0] out_ch; reg [2:0] wait_cnt;
    reg [15:0] pool_buffer [0:2];
    reg [3:0] bg_bit_cnt; reg [15:0] bg_buffer; 
    reg bg_we; 
    reg [15:0] bg_data;
    
    // Giải mã Threshold dựa trên định dạng 8-bit mới của CONV2
    // Khôi phục bit Polarity (wt_data[15]) cho lớp CONV2
    // Sửa lại dòng assign thresh_val ở đầu file control_fsm.v
    // TRẢ LẠI BẢN GỐC (Bắt đúng nhịp 15 và dùng out_ch)
    assign thresh_val = (state == S_CV2_C && pixel_cnt[3:0] == 4'd15) ? 
                        (center_pixel[out_ch] ? {wt_data[15], 7'd0, wt_data[23:16]} : {wt_data[15], 7'd0, wt_data[31:24]}) : 
                        wt_data[31:16];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin bg_bit_cnt <= 0; bg_we <= 0; bg_buffer <= 0; bg_data <= 0; fc_buffer <= 16'd0; end
        else begin
            bg_we <= 0;
            if (state == S_IDLE) bg_bit_cnt <= 0;
            else if (valid_out_fb && state != S_FC2 && state != S_DONE) begin
                bg_buffer <= {datapath_out, bg_buffer[15:1]};
                if (bg_bit_cnt == 15) begin
                    bg_we <= 1; bg_data <= {datapath_out, bg_buffer[15:1]};
                    bg_bit_cnt <= 0;
                end else bg_bit_cnt <= bg_bit_cnt + 1;
            end
        end
    end

    reg pool_we; reg [15:0] pool_data;
    
    // TRẢ LẠI LOGIC GỐC: Chỉ xài bg_we và pool_we
    assign act_we = bg_we | pool_we;
    assign act_wr_data = pool_we ? pool_data : bg_data;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) act_wr_addr <= 0;
        else begin
            if (state == S_IDLE && frame_done) act_wr_addr <= 72; 
            else if (state == S_WAIT && wait_cnt==3) begin
                if (next_state_save == S_FC1) act_wr_addr <= 972;       
                else if (is_conv2) act_wr_addr <= 792; 
            end
            else if (state == S_POOL1 && pixel_cnt == 4) act_wr_addr <= 648 + pad_y*12 + pad_x;
            else if (state == S_POOL2 && pixel_cnt == 4) act_wr_addr <= 936 + pad_y*6 + pad_x;
            else if (bg_we) act_wr_addr <= act_wr_addr + 1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; pad_x <= 0; pad_y <= 0; out_ch <= 0; in_ch <= 0; pixel_cnt <= 0; wt_addr <= 0;
            shift_en <= 0; valid_in <= 0; pool_we <= 0; result <= 0; done <= 0; acc_clr <= 0; is_acc_done <= 0;
        end else begin
            shift_en <= 0; valid_in <= 0; pool_we <= 0; acc_clr <= 0; is_acc_done <= 0;

            case (state)
                S_IDLE: if (frame_done) begin 
                    state <= S_PR1_A;
                    pixel_cnt <= 0; wt_addr <= 0; is_conv2 <= 0; is_fc <= 0;
                    is_img_read <= 1; // <--- SỬA LỖI 0000 TẠI ĐÂY (Bật cờ sớm 1 nhịp)
                end
                
                S_PR1_A: begin act_rd_addr <= pixel_cnt; is_img_read <= 1; state <= S_PR1_S; end
                S_PR1_S: begin shift_en <= 1; state <= S_PR1_C; end
                S_PR1_C: begin
                    if (pixel_cnt == 24) begin state <= S_CV1_A; pixel_cnt <= 0; out_ch <= 0; wt_addr <= 0; end
                    else begin pixel_cnt <= pixel_cnt + 1; state <= S_PR1_A; end
                end

                S_CV1_A: begin act_rd_addr <= pad_y*24 + pad_x + 25; is_img_read <= 1; wt_addr <= 0; state <= S_CV1_S; end
                S_CV1_S: begin 
                    shift_en <= 1; // Nhịp sau (SHIFT) sẽ tiến hành dịch cửa sổ
                    state <= S_CV1_SHIFT; 
                end
                
                // FIX 2: Thêm trạng thái chờ dịch cửa sổ xong mới tính
                S_CV1_SHIFT: begin
                    out_ch <= 0; pixel_cnt <= 0; wt_addr <= 0; 
                    state <= S_CV1_C;
                    
                    // Bật cờ để Datapath đón Filter 0 ngay trong nhịp S_CV1_C tiếp theo
                    valid_in <= 1;
                    acc_clr <= 1;
                    is_acc_done <= 1;
                end
                
                S_CV1_C: begin
                    if (pixel_cnt < 15) wt_addr <= pixel_cnt + 1;
                    
                    // FIX 3: Luôn giữ cờ trong suốt 16 nhịp tính toán (pixel_cnt từ 0 đến 15)
                    valid_in <= 1; 
                    acc_clr <= 1;
                    is_acc_done <= 1;

                    if (pixel_cnt == 15) begin
                        pixel_cnt <= 0;
                        
                        // FIX 4: Chỉ ngắt cờ khi rời khỏi trạng thái
                        valid_in <= 0; 
                        acc_clr <= 0;
                        is_acc_done <= 0;

                        if (pad_x == 23 && pad_y == 23) begin state <= S_WAIT; next_state_save <= S_POOL1; wait_cnt <= 0; end
                        else begin state <= S_CV1_A; if (pad_x == 23) begin pad_x <= 0; pad_y <= pad_y + 1; end else pad_x <= pad_x + 1; end
                    end else begin
                        pixel_cnt <= pixel_cnt + 1;
                    end
                end

                S_WAIT: begin 
                    if (wait_cnt == 3) begin 
                        state <= next_state_save; pad_x <= 0; pad_y <= 0; pixel_cnt <= 0; in_ch <= 0; out_ch <= 0;
                        if (next_state_save == S_FC1) begin act_rd_addr <= 936; wt_addr <= 272; end
                        if (next_state_save == S_FC2) begin act_rd_addr <= 972; wt_addr <= 2576; end
                    end else wait_cnt <= wait_cnt + 1; 
                end

                S_POOL1: begin
                    is_img_read <= 0;
                    
                    // Cấp địa chỉ RAM ở các nhịp 0, 1, 2, 3
                    if (pixel_cnt < 4) begin
                        act_rd_addr <= 72 + (pad_y*2 + pixel_cnt[1])*24 + (pad_x*2 + pixel_cnt[0]);
                    end

                    // Hứng dữ liệu từ RAM trả về ở các nhịp 2, 3, 4
                    if (pixel_cnt >= 2 && pixel_cnt <= 4) begin
                        pool_buffer[pixel_cnt-2] <= act_rd_data;
                    end

                    // Nhịp 5: Nhận dữ liệu cuối cùng (Pixel 3) và ghi kết quả
                    if (pixel_cnt == 5) begin
                        pool_we <= 1; 
                        pool_data <= pool_buffer[0] | pool_buffer[1] | pool_buffer[2] | act_rd_data;
                        pixel_cnt <= 0;
                        if (pad_x == 11 && pad_y == 11) begin 
                            state <= S_WAIT; next_state_save <= S_PR2_A; wait_cnt <= 0; is_conv2 <= 1; 
                        end else if (pad_x == 11) begin 
                            pad_x <= 0; pad_y <= pad_y + 1; 
                        end else begin
                            pad_x <= pad_x + 1;
                        end
                    end else begin
                        pixel_cnt <= pixel_cnt + 1;
                    end
                end

                // SỬA LỖI 0000 Ở ĐÂY: Thêm is_img_read <= 0 để đọc đúng RAM
                S_PR2_A: begin act_rd_addr <= 648 + pixel_cnt; is_conv2 <= 1; is_img_read <= 0; state <= S_PR2_S; end
                S_PR2_S: begin shift_en <= 1; state <= S_PR2_C; end
                
                // TRẢ LẠI BẢN GỐC: pixel_cnt == 12
                S_PR2_C: begin
                    if (pixel_cnt == 12) begin state <= S_CV2_A; pixel_cnt <= 0; out_ch <= 0; in_ch <= 0; wt_addr <= 16; end
                    else begin pixel_cnt <= pixel_cnt + 1; state <= S_PR2_A; end
                end

                S_CV2_A: begin act_rd_addr <= 648 + pad_y*12 + pad_x + 13; wt_addr <= 16; state <= S_CV2_S; end
                S_CV2_S: begin 
                    shift_en <= 1;
                    state <= S_CV2_SHIFT;
                end
                
                S_CV2_SHIFT: begin 
                    pixel_cnt <= 0; out_ch <= 0; in_ch <= 0; wt_addr <= 16; 
                    state <= S_CV2_C;
                    
                    valid_in <= 1;
                    acc_clr <= 1;       
                    is_acc_done <= 0;   
                end
                
                // TRẢ LẠI BẢN GỐC HOÀN TOÀN CỦA BÁC
                S_CV2_C: begin
                    if (pixel_cnt < 255) wt_addr <= wt_addr + 1;
                    
                    if (pixel_cnt == 255) begin
                        pixel_cnt <= 0;
                        in_ch <= 0; out_ch <= 0;
                        
                        valid_in <= 0; 
                        acc_clr <= 0; 
                        is_acc_done <= 0; 

                        if (pad_x == 11 && pad_y == 11) begin 
                            state <= S_WAIT; next_state_save <= S_POOL2; wait_cnt <= 0; 
                        end else begin 
                            state <= S_CV2_A; 
                            if (pad_x == 11) begin 
                                pad_x <= 0; pad_y <= pad_y + 1; 
                            end else begin 
                                pad_x <= pad_x + 1; 
                            end
                        end
                    end else begin
                        valid_in <= 1;
                        
                        // ĐÂY LÀ NHỊP THẦN THÁNH DO BÁC CĂN (14 và 15) - GIỮ NGUYÊN!
                        is_acc_done <= (pixel_cnt[3:0] == 4'd14); 
                        acc_clr     <= (pixel_cnt[3:0] == 4'd15); 

                        pixel_cnt <= pixel_cnt + 1;
                        out_ch <= (pixel_cnt + 1) >> 4;
                        in_ch  <= (pixel_cnt + 1) & 4'hF;
                    end
                end

                S_POOL2: begin
                    is_conv2 <= 0; 
                    
                    // Cấp địa chỉ RAM ở các nhịp 0, 1, 2, 3
                    if (pixel_cnt < 4) begin
                        act_rd_addr <= 792 + (pad_y*2 + pixel_cnt[1])*12 + (pad_x*2 + pixel_cnt[0]);
                    end

                    // Hứng dữ liệu từ RAM trả về ở các nhịp 2, 3, 4
                    if (pixel_cnt >= 2 && pixel_cnt <= 4) begin
                        pool_buffer[pixel_cnt-2] <= act_rd_data;
                    end

                    // Nhịp 5: Nhận dữ liệu cuối cùng và ghi kết quả
                    if (pixel_cnt == 5) begin
                        pool_we <= 1; 
                        pool_data <= pool_buffer[0] | pool_buffer[1] | pool_buffer[2] | act_rd_data;
                        pixel_cnt <= 0;
                        if (pad_x == 5 && pad_y == 5) begin 
                            state <= S_WAIT; next_state_save <= S_FC1; wait_cnt <= 0; is_fc <= 1; out_ch <= 0; 
                        end else if (pad_x == 5) begin 
                            pad_x <= 0; pad_y <= pad_y + 1; 
                        end else begin
                            pad_x <= pad_x + 1;
                        end
                    end else begin
                        pixel_cnt <= pixel_cnt + 1;
                    end
                end

                S_FC1: begin
                    is_conv2 <= 0;
                    is_fc <= 1;

                    // 1. Tính toán địa chỉ GHI cho lớp FC1 (từ 972 đến 975)
                    // Logic này giúp bg_we tự động ghi đúng ô nhớ khi nén đủ 16 bit
                    if (out_ch > 0)
                        act_wr_addr <= 972 + ((out_ch - 1) >> 4);
                    else
                        act_wr_addr <= 972;

                    // 2. Cấp địa chỉ ĐỌC RAM (POOL2 từ 936 đến 971)
                    if (pixel_cnt < 36) 
                        act_rd_addr <= 936 + pixel_cnt;

                    // 3. Cấp địa chỉ ROM Trọng số (Bắt đầu từ 272)
                    if (out_ch == 0 && pixel_cnt == 0) begin
                        wt_addr <= 272;
                    end else if (pixel_cnt >= 2 && pixel_cnt <= 36) begin
                        wt_addr <= wt_addr + 1;
                    end else if (pixel_cnt == 0 && out_ch > 0) begin
                        wt_addr <= wt_addr + 1; // Nhảy sang nơ-ron tiếp theo
                    end
                    // Chú ý: Ở nhịp 37, wt_addr ĐỨNG IM để giữ đúng Threshold!

                    // 4. Logic điều khiển chu kỳ 38 nhịp (0-37)
                    if (pixel_cnt == 37) begin
                        pixel_cnt <= 0;
                        if (out_ch == 63) begin
                            state <= S_WAIT; next_state_save <= S_FC2; wait_cnt <= 0; out_ch <= 0;
                        end else begin
                            state <= S_FC1;
                            out_ch <= out_ch + 1;
                        end
                    end else begin
                        pixel_cnt <= pixel_cnt + 1;
                    end
                    
                    // 5. Cờ điều khiển Datapath
                    // 5. Cờ điều khiển Datapath
                    valid_in <= (pixel_cnt >= 1 && pixel_cnt <= 36);
                    is_acc_done <= (pixel_cnt == 36); 
                    // SỬA Ở ĐÂY: Xóa bộ cộng ở nhịp dữ liệu ĐẦU TIÊN (thay vì nhịp cuối)
                    acc_clr <= (pixel_cnt == 1);
                end
                S_FC2: begin
                    is_conv2 <= 0;
                    is_fc <= 1;
                    is_img_read <= 0; 

                    // 1. Cấp địa chỉ RAM (Tăng từ nhịp 0 đến 3)
                    if (pixel_cnt < 4) begin
                        act_rd_addr <= 972 + pixel_cnt;
                    end

                    // 2. Cấp địa chỉ ROM (ĐỨNG IM ở nhịp 1 để đợi RAM ra dữ liệu)
                    if (pixel_cnt == 0) begin
                        wt_addr <= 2576;
                    end else if (pixel_cnt >= 2 && pixel_cnt <= 4) begin
                        wt_addr <= wt_addr + 1;
                    end

                    // 3. Kích hoạt cờ điều khiển
                    valid_in    <= (pixel_cnt >= 1 && pixel_cnt <= 4);
                    acc_clr     <= (pixel_cnt == 1); 
                    is_acc_done <= (pixel_cnt == 4); 

                    // 4. Vòng lặp 6 nhịp
                    if (pixel_cnt == 5) begin
                        pixel_cnt <= 0;
                        state <= S_DONE;
                    end else begin
                        pixel_cnt <= pixel_cnt + 1;
                    end
                end
                
                S_DONE: begin
                    result <= datapath_out; // Chốt bit kết quả từ Datapath
                    done <= 1;              // Vẫy cờ báo hiệu hoàn thành toàn mạng!
                end


            endcase
        end
    end
endmodule