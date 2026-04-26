`timescale 1ns / 1ps

module control_fsm (
    input  wire clk, rst_n, frame_done, valid_out_fb, datapath_out,
    input  wire [31:0] wt_data, 
    input  wire [15:0] center_pixel, 
    input  wire [15:0] act_rd_data, 
    
    output reg [11:0] wt_addr, 
    output reg [10:0] act_rd_addr, act_wr_addr,
    
    output wire act_we,             
    output wire [15:0] act_wr_data, 
    
    output reg shift_en, is_conv2, is_fc, is_img_read,
    output reg [4:0] pad_x, pad_y, in_ch,
    output reg valid_in, acc_clr, is_acc_done,
    output wire [15:0] thresh_val,
    output reg result, done,   
    output wire busy,
    input  wire [11:0] current_pop, // <--- THÊM: Đón dây từ datapath
    output reg  [5:0]  fc2_pop      // <--- THÊM: Lưu lại Popcount cuối cùng      
);
    

    // =========================================================================
    // KHAI BÁO BIẾN TRẠNG THÁI (ĐÃ ĐỔI TÊN RÕ RÀNG VÀ NGẮN GỌN)
    // =========================================================================
    localparam IDLE            = 0;
    localparam CONV1_PRE_ADDR  = 1;
    localparam CONV1_PRE_SHIFT = 2;
    localparam CONV1_PRE_CHECK = 3;
    localparam CONV1_ADDR      = 4;
    localparam CONV1_SHIFT     = 5;
    localparam CONV1_CALC      = 6;
    localparam CONV1_SETUP     = 19;
    
    localparam WAIT_SYNC       = 7;
    localparam POOL1           = 8;
    
    localparam CONV2_PRE_ADDR  = 9;
    localparam CONV2_PRE_SHIFT = 10;
    localparam CONV2_PRE_CHECK = 11;
    localparam CONV2_ADDR      = 12;
    localparam CONV2_SHIFT     = 13;
    localparam CONV2_CALC      = 14;
    localparam CONV2_SETUP     = 20;
    
    localparam POOL2           = 15;
    localparam FC1             = 16;
    localparam FC2             = 17;
    localparam DONE            = 18;

    // =========================================================================
    // KHAI BÁO THANH GHI NỘI BỘ
    // =========================================================================
    reg [4:0] state, next_state_save;
    reg [9:0] pixel_cnt; 
    reg [5:0] out_ch; 
    reg [2:0] wait_cnt;
    
    reg [15:0] pool_buffer [0:2];
    reg [3:0]  bg_bit_cnt; 
    reg [15:0] bg_buffer; 
    reg        bg_we; 
    reg [15:0] bg_data;
    
    reg        pool_we; 
    reg [15:0] pool_data;

    // LOGIC THRESHOLD
    assign thresh_val = (state == CONV2_CALC && pixel_cnt[3:0] == 4'd15) ? 
                        (center_pixel[out_ch] ? {wt_data[15], 7'd0, wt_data[23:16]} : {wt_data[15], 7'd0, wt_data[31:24]}) : 
                        wt_data[31:16];

    // =========================================================================
    // GHI KẾT QUẢ VÀO RAM (BIT PACKER & POOLING)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin 
            bg_bit_cnt <= 0; 
            bg_we      <= 0; 
            bg_buffer  <= 0; 
            bg_data    <= 0; 
        end else begin
            bg_we <= 0;
            
            if (state == IDLE) begin
                bg_bit_cnt <= 0;
            end else if (valid_out_fb && state != FC2 && state != DONE) begin
                bg_buffer <= {datapath_out, bg_buffer[15:1]};
                
                if (bg_bit_cnt == 15) begin
                    bg_we      <= 1; 
                    bg_data    <= {datapath_out, bg_buffer[15:1]};
                    bg_bit_cnt <= 0;
                end else begin
                    bg_bit_cnt <= bg_bit_cnt + 1;
                end
            end
        end
    end

    assign act_we      = bg_we | pool_we;
    assign act_wr_data = pool_we ? pool_data : bg_data;

    // KHỐI QUẢN LÝ ĐỊA CHỈ GHI BRAM (act_wr_addr)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            act_wr_addr <= 0;
        end else begin
            if (state == IDLE && frame_done) begin
                act_wr_addr <= 72; 
            end 
            else if (state == WAIT_SYNC && wait_cnt == 3) begin
                if (next_state_save == FC1) begin
                    act_wr_addr <= 972;       
                end else if (is_conv2) begin
                    act_wr_addr <= 792; 
                end
            end
            else if (state == POOL1 && pixel_cnt == 4) begin
                act_wr_addr <= 648 + pad_y*12 + pad_x;
            end
            else if (state == POOL2 && pixel_cnt == 4) begin
                act_wr_addr <= 936 + pad_y*6 + pad_x;
            end
            else if (state == FC1) begin
                if (out_ch > 0) begin
                    act_wr_addr <= 972 + ((out_ch - 1) >> 4);
                end else begin
                    act_wr_addr <= 972;
                end
            end
            else if (bg_we) begin
                act_wr_addr <= act_wr_addr + 1;
            end
        end
    end

    // =========================================================================
    // MÁY TRẠNG THÁI FSM CHÍNH
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= IDLE; 
            pad_x           <= 0; 
            pad_y           <= 0; 
            out_ch          <= 0; 
            in_ch           <= 0; 
            pixel_cnt       <= 0; 
            wt_addr         <= 0;
            shift_en        <= 0; 
            valid_in        <= 0; 
            pool_we         <= 0; 
            result          <= 0; 
            done            <= 0; 
            acc_clr         <= 0; 
            is_acc_done     <= 0;
            is_conv2        <= 0; 
            is_fc           <= 0; 
            is_img_read     <= 0; 
            wait_cnt        <= 0; 
            next_state_save <= 0;
            act_rd_addr     <= 0; 
            pool_data       <= 0;
            pool_buffer[0]  <= 0; 
            pool_buffer[1]  <= 0; 
            pool_buffer[2]  <= 0;
        end else begin
            shift_en    <= 0; 
            valid_in    <= 0; 
            pool_we     <= 0; 
            acc_clr     <= 0; 
            is_acc_done <= 0;

            case (state)
                IDLE: begin
                    done <= 0; // <--- THÊM DÒNG NÀY ĐỂ XÓA CỜ DONE
                    if (frame_done) begin 
                        state       <= CONV1_PRE_ADDR;
                        pixel_cnt   <= 0; 
                        wt_addr     <= 0; 
                        is_conv2    <= 0;
                        is_fc       <= 0; 
                        is_img_read <= 1;
                    end
                end
                
                CONV1_PRE_ADDR: begin 
                    act_rd_addr <= pixel_cnt; 
                    is_img_read <= 1; 
                    state       <= CONV1_PRE_SHIFT; 
                end
                
                CONV1_PRE_SHIFT: begin 
                    shift_en <= 1; 
                    state    <= CONV1_PRE_CHECK; 
                end
                
                CONV1_PRE_CHECK: begin
                    if (pixel_cnt == 24) begin 
                        state     <= CONV1_ADDR; 
                        pixel_cnt <= 0; 
                        out_ch    <= 0; 
                        wt_addr   <= 0; 
                    end else begin 
                        pixel_cnt <= pixel_cnt + 1; 
                        state     <= CONV1_PRE_ADDR; 
                    end
                end

                CONV1_ADDR: begin 
                    act_rd_addr <= pad_y*24 + pad_x + 25; 
                    is_img_read <= 1; 
                    wt_addr     <= 0; 
                    state       <= CONV1_SHIFT; 
                end
                
                // CONV1_SHIFT (sửa):
CONV1_SHIFT: begin 
    shift_en <= 1; 
    wt_addr  <= 0;   // <-- THÊM: pre-fetch weight[0] cho cycle tiếp theo
    state    <= CONV1_SETUP; 
end

// CONV1_SETUP (sửa):
CONV1_SETUP: begin 
    out_ch      <= 0; 
    pixel_cnt   <= 0; 
    // wt_addr  <= 0;  <-- XÓA dòng này, đã set ở CONV1_SHIFT rồi
    wt_addr     <= 1; // pre-fetch addr 1 cho CONV1_CALC cycle đầu
    state       <= CONV1_CALC;
    valid_in    <= 1; 
    acc_clr     <= 1; 
    is_acc_done <= 1;
end

// CONV1_CALC (sửa):
CONV1_CALC: begin
    if (pixel_cnt < 15) begin
        wt_addr <= pixel_cnt + 2; // thay vì pixel_cnt + 1, pre-fetch trước 1
    end
                    
                    valid_in    <= 1; 
                    acc_clr     <= 1; 
                    is_acc_done <= 1;

                    if (pixel_cnt == 15) begin
                        pixel_cnt   <= 0; 
                        valid_in    <= 0; 
                        acc_clr     <= 0; 
                        is_acc_done <= 0;
                        
                        if (pad_x == 23 && pad_y == 23) begin 
                            state           <= WAIT_SYNC; 
                            next_state_save <= POOL1; 
                            wait_cnt        <= 0; 
                        end else begin 
                            state <= CONV1_ADDR; 
                            if (pad_x == 23) begin 
                                pad_x <= 0; 
                                pad_y <= pad_y + 1; 
                            end else begin 
                                pad_x <= pad_x + 1; 
                            end 
                        end
                    end else begin
                        pixel_cnt <= pixel_cnt + 1;
                    end
                end

                WAIT_SYNC: begin 
                    if (wait_cnt == 3) begin 
                        state     <= next_state_save; 
                        pad_x     <= 0; 
                        pad_y     <= 0; 
                        pixel_cnt <= 0; 
                        in_ch     <= 0; 
                        out_ch    <= 0;
                        
                        if (next_state_save == FC1) begin 
                            act_rd_addr <= 936; 
                            wt_addr     <= 272; // pre-fetch cho FC1 (Không đổi)
                        end
                        if (next_state_save == FC2) begin 
                            act_rd_addr <= 972; 
                            wt_addr     <= 1424; // SỬA Ở ĐÂY: 2576 đổi thành 1424
                        end
                    end else begin
                        wait_cnt <= wait_cnt + 1; 
                    end
                end

                POOL1: begin
                    is_img_read <= 0;
                    
                    if (pixel_cnt < 4) begin
                        act_rd_addr <= 72 + (pad_y*2 + pixel_cnt[1])*24 + (pad_x*2 + pixel_cnt[0]);
                    end

                    if (pixel_cnt >= 2 && pixel_cnt <= 4) begin
                        pool_buffer[pixel_cnt-2] <= act_rd_data;
                    end

                    if (pixel_cnt == 5) begin
                        pool_we   <= 1; 
                        pool_data <= pool_buffer[0] | pool_buffer[1] | pool_buffer[2] | act_rd_data;
                        pixel_cnt <= 0;
                        
                        if (pad_x == 11 && pad_y == 11) begin 
                            state           <= WAIT_SYNC; 
                            next_state_save <= CONV2_PRE_ADDR; 
                            wait_cnt        <= 0; 
                            is_conv2        <= 1; 
                        end else if (pad_x == 11) begin 
                            pad_x <= 0; 
                            pad_y <= pad_y + 1; 
                        end else begin
                            pad_x <= pad_x + 1;
                        end
                    end else begin
                        pixel_cnt <= pixel_cnt + 1;
                    end
                end

                CONV2_PRE_ADDR: begin 
                    act_rd_addr <= 648 + pixel_cnt; 
                    is_conv2    <= 1; 
                    is_img_read <= 0; 
                    state       <= CONV2_PRE_SHIFT; 
                end
                
                CONV2_PRE_SHIFT: begin 
                    shift_en <= 1; 
                    state    <= CONV2_PRE_CHECK; 
                end
                
                CONV2_PRE_CHECK: begin
                    if (pixel_cnt == 12) begin 
                        state     <= CONV2_ADDR; 
                        pixel_cnt <= 0; 
                        out_ch    <= 0; 
                        in_ch     <= 0; 
                        wt_addr   <= 16; 
                    end else begin 
                        pixel_cnt <= pixel_cnt + 1; 
                        state     <= CONV2_PRE_ADDR; 
                    end
                end

                CONV2_ADDR: begin 
                    act_rd_addr <= 648 + pad_y*12 + pad_x + 13; 
                    wt_addr     <= 16; 
                    state       <= CONV2_SHIFT; 
                end
                
                CONV2_SHIFT: begin 
    shift_en <= 1; 
    wt_addr  <= 16;  // pre-fetch
    state    <= CONV2_SETUP; 
end

CONV2_SETUP: begin 
    pixel_cnt   <= 0; 
    out_ch      <= 0; 
    in_ch       <= 0; 
    wt_addr     <= 17; // pre-fetch addr tiếp theo
    state       <= CONV2_CALC;
    valid_in    <= 1; 
    acc_clr     <= 1; 
    is_acc_done <= 0;   
end

CONV2_CALC: begin
    if (pixel_cnt < 255) begin
        wt_addr <= wt_addr + 1; // giữ nguyên nhưng logic đã offset 1
    end
                    
                    if (pixel_cnt == 255) begin
                        pixel_cnt   <= 0; 
                        in_ch       <= 0; 
                        out_ch      <= 0;
                        valid_in    <= 0; 
                        acc_clr     <= 0; 
                        is_acc_done <= 0; 

                        if (pad_x == 11 && pad_y == 11) begin 
                            state           <= WAIT_SYNC; 
                            next_state_save <= POOL2; 
                            wait_cnt        <= 0; 
                        end else begin 
                            state <= CONV2_ADDR; 
                            if (pad_x == 11) begin 
                                pad_x <= 0; 
                                pad_y <= pad_y + 1; 
                            end else begin 
                                pad_x <= pad_x + 1; 
                            end
                        end
                    end else begin
                        valid_in    <= 1;
                        is_acc_done <= (pixel_cnt[3:0] == 4'd14); 
                        acc_clr     <= (pixel_cnt[3:0] == 4'd15); 
                        pixel_cnt   <= pixel_cnt + 1;
                        out_ch      <= (pixel_cnt + 1) >> 4;
                        in_ch       <= (pixel_cnt + 1) & 4'hF;
                    end
                end

                POOL2: begin
                    is_conv2 <= 0; 
                    
                    if (pixel_cnt < 4) begin
                        act_rd_addr <= 792 + (pad_y*2 + pixel_cnt[1])*12 + (pad_x*2 + pixel_cnt[0]);
                    end

                    if (pixel_cnt >= 2 && pixel_cnt <= 4) begin
                        pool_buffer[pixel_cnt-2] <= act_rd_data;
                    end

                    if (pixel_cnt == 5) begin
                        pool_we   <= 1; 
                        pool_data <= pool_buffer[0] | pool_buffer[1] | pool_buffer[2] | act_rd_data;
                        pixel_cnt <= 0;
                        
                        if (pad_x == 5 && pad_y == 5) begin 
                            state           <= WAIT_SYNC; 
                            next_state_save <= FC1; 
                            wait_cnt        <= 0; 
                            is_fc           <= 1; 
                            out_ch          <= 0; 
                        end else if (pad_x == 5) begin 
                            pad_x <= 0; 
                            pad_y <= pad_y + 1; 
                        end else begin
                            pad_x <= pad_x + 1;
                        end
                    end else begin
                        pixel_cnt <= pixel_cnt + 1;
                    end
                end

                // WAIT_SYNC: giữ nguyên wt_addr <= 272 ✓ (đã đúng)

                FC1: begin
                    is_conv2 <= 0;
                    is_fc    <= 1;

                    if (pixel_cnt < 36) begin
                        act_rd_addr <= 936 + pixel_cnt;
                    end

                    if (pixel_cnt >= 1 && pixel_cnt <= 35) begin
                        wt_addr <= wt_addr + 1;
                    end else if (pixel_cnt == 0 && out_ch > 0) begin
                        wt_addr <= wt_addr + 1;
                    end

                    if (pixel_cnt == 37) begin
                        pixel_cnt <= 0;
                        if (out_ch == 31) begin // SỬA Ở ĐÂY: 63 đổi thành 31
                            state           <= WAIT_SYNC;
                            next_state_save <= FC2;
                            wait_cnt        <= 0;
                            out_ch          <= 0;
                        end else begin
                            state  <= FC1;
                            out_ch <= out_ch + 1;
                        end
                    end else begin
                        pixel_cnt <= pixel_cnt + 1;
                    end

                    valid_in    <= (pixel_cnt >= 1 && pixel_cnt <= 36);
                    is_acc_done <= (pixel_cnt == 36);
                    acc_clr     <= (pixel_cnt == 1);
                end
                
                FC2: begin
                    is_conv2    <= 0;
                    is_fc       <= 1;
                    is_img_read <= 0;

                    if (pixel_cnt < 2) begin // SỬA: Đọc 2 chunk thay vì 4
                        act_rd_addr <= 972 + pixel_cnt;
                    end

                    // pixel_cnt=0: KHÔNG SET wt_addr → giữ nguyên 1424 từ WAIT_SYNC
                    // pixel_cnt=1: tăng để pre-fetch cho cycle tiếp theo
                    // pixel_cnt=2: không cần (wt_data đã sẵn)
                    if (pixel_cnt == 1) begin // SỬA: Chỉ tăng wt_addr ở cycle 1
                        wt_addr <= wt_addr + 1;
                    end

                    valid_in    <= (pixel_cnt >= 1 && pixel_cnt <= 2); // SỬA: 4 thành 2
                    acc_clr     <= (pixel_cnt == 1);
                    is_acc_done <= (pixel_cnt == 2); // SỬA: 4 thành 2

                    if (pixel_cnt == 4) begin // SỬA: 5 thành 3 (Kết thúc sớm hơn)
                        pixel_cnt <= 0;
                        state     <= DONE;
                    end else begin
                        pixel_cnt <= pixel_cnt + 1;
                    end
                end
                
                DONE: begin
                    result  <= datapath_out;
                    done    <= 1;        
                    fc2_pop <= current_pop[5:0]; // <--- THÊM: Bắt dính con số 24 tại đây!
                    state   <= IDLE;      
                end
            endcase
        end
    end
    assign busy = (state != IDLE);
endmodule