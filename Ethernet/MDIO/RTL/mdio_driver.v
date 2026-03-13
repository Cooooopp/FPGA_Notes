module mdio_driver (
    input  wire        clk,         // 100MHz 系统主时钟
    input  wire        rst_n,       // 异步复位，低电平有效
    
    // ---------------- PHY 物理引脚 ----------------
    output wire        mdc,         // MDIO 管理时钟 (6.25MHz)
    inout  wire        mdio,        // MDIO 双向数据线
    
    // ---------------- 用户侧逻辑接口 ----------------
    input  wire        i_start,       // 拉高一个时钟周期触发传输
    input  wire        i_wh_rl,       // 1: 写寄存器, 0: 读寄存器
    input  wire [4:0]  i_phy_addr,    // PHY 芯片硬件地址
    input  wire [4:0]  i_reg_addr,    // 目标内部寄存器地址
    input  wire [15:0] i_write_data,  // 准备写入的 16 位数据
    output wire [15:0] o_read_data,   // 读取到的 16 位数据
    output wire        o_done         // 传输完成标志 (拉高一拍)
);

/*---------------------------------------------------------*\
                        三态mdio方向
\*---------------------------------------------------------*/
reg  r_mdio_out;
reg  r_mdio_dir; // 1: 输出, 0: 高阻态(输入)
wire w_mdio_in;
assign mdio    = r_mdio_dir ? r_mdio_out : 1'bz;
assign w_mdio_in = mdio;

/*---------------------------------------------------------*\
                        分频做mdc
\*---------------------------------------------------------*/
reg [2:0]   r_cnt_mdcdiv;
reg         r_mdc;
assign mdc = r_mdc;
always @(posedge clk) begin
    if(rst_n==1'b0)
        r_cnt_mdcdiv <= 3'd0;
    else 
        r_cnt_mdcdiv <= r_cnt_mdcdiv + 1'b1;
end
always @(posedge clk) begin
    if(rst_n==1'b0)
        r_mdc <= 1'b0;
    else if(r_cnt_mdcdiv == 3'b111)
        r_mdc <= ~r_mdc;
end

reg r_mdc_fall;
reg r_mdc_rise;
always @(posedge clk) begin
    if(rst_n==1'b0)
        r_mdc_fall <= 1'b0;
    else if(r_mdc == 1'b1 && r_cnt_mdcdiv == 3'b110)
        r_mdc_fall <= 1'b1;
    else 
        r_mdc_fall <= 1'b0;
end
always @(posedge clk) begin
    if(rst_n==1'b0)
        r_mdc_rise <= 1'b0;
    else if(r_mdc == 1'b0 && r_cnt_mdcdiv == 3'b110)
        r_mdc_rise <= 1'b1;
    else 
        r_mdc_rise <= 1'b0;
end

/*---------------------------------------------------------*\
                        状态机
\*---------------------------------------------------------*/
localparam IDLE = 3'd0;
localparam PRE  = 3'd1;
localparam CTRL = 3'd2;
localparam TA   = 3'd3;
localparam DATA = 3'd4;

reg [2:0]   r_cur_state;
reg [2:0]   r_next_state;
reg [5:0]   r_cnt_bit;


always @(posedge clk) begin
    if(rst_n==1'b0)
        r_cur_state <= IDLE;
    else 
        r_cur_state <= r_next_state;
end

always@(*) begin
    r_next_state = r_cur_state;
    case(r_cur_state)
        IDLE : r_next_state = (i_start) ? PRE : IDLE ;
        PRE  : r_next_state = (r_cnt_bit == 6'd31 && r_mdc_fall==1'b1) ? CTRL : PRE;
        CTRL : r_next_state = (r_cnt_bit == 6'd13 && r_mdc_fall==1'b1) ? TA : CTRL;
        TA   : r_next_state = (r_cnt_bit == 6'd1 && r_mdc_fall==1'b1) ? DATA : TA;
        DATA : r_next_state = (r_cnt_bit == 6'd15 && r_mdc_fall==1'b1) ? IDLE : DATA;
        default : r_next_state = IDLE;
    endcase
end

reg [15:0]  r_done_shift;

// r_mdio_out
// r_mdio_dir
// r_cnt_bit
reg [15:0]  r_shiftreg_data;
reg [13:0]  r_shiftreg_ctrl;
reg [15:0]  r_read_data    ;
reg         r_done         ;
assign o_read_data = r_read_data;
assign o_done      = r_done_shift[15];
always @(posedge clk) r_done_shift <= {r_done_shift[14:0],r_done};
wire [1:0]  w_operation = (i_wh_rl) ? 2'b01 : 2'b10 ; 
always @(posedge clk) begin
    if(rst_n==1'b0) begin
        r_mdio_dir      <= 1'b0;
        r_cnt_bit       <= 6'd0;
        r_mdio_out      <= 1'b0;
        r_shiftreg_ctrl <= 14'd0;
        r_shiftreg_data <= 16'd0;
        r_read_data     <= 16'd0;
        r_done          <= 1'b0;
    end

    else begin
        r_done <= 1'b0;
        if(r_cur_state == IDLE && i_start == 1'b1) begin
            r_shiftreg_ctrl <= {2'b01, w_operation, i_phy_addr, i_reg_addr};
            r_shiftreg_data <= i_write_data;
            r_read_data     <= 16'd0;
        end

        if(r_mdc_fall == 1'b1) begin
            case(r_cur_state)
                IDLE : begin
                    r_mdio_dir  <= 1'b0;
                    r_cnt_bit   <= 6'd0;
                    r_mdio_out  <= 1'b0;
                    // r_read_data <= 16'd0;
                    //r_done      <= 1'b0;
                    // if(i_start == 1'b1) begin
                    //     r_shiftreg_ctrl <= {2'b01,w_operation,i_phy_addr,i_reg_addr};
                    //     r_shiftreg_data <= i_write_data;
                    // end
                end
                PRE : begin
                    r_mdio_dir      <= 1'b1;
                    r_mdio_out      <= 1'b1;
                    r_shiftreg_ctrl <= r_shiftreg_ctrl;
                    r_shiftreg_data <= r_shiftreg_data;
                    r_read_data     <= 16'd0;
                    r_done          <= 1'b0;
                    if(r_cnt_bit >= 6'd31)
                        r_cnt_bit <= 6'd0;
                    else
                        r_cnt_bit <= r_cnt_bit + 1'b1;
                end
                CTRL : begin
                    r_mdio_dir      <= 1'b1;
                    r_mdio_out      <= r_shiftreg_ctrl[13];
                    r_shiftreg_ctrl <= {r_shiftreg_ctrl[12:0],1'b0};
                    r_shiftreg_data <= r_shiftreg_data;
                    r_read_data     <= 16'd0;
                    r_done          <= 1'b0;
                    if(r_cnt_bit >= 6'd13)
                        r_cnt_bit <= 6'd0;
                    else
                        r_cnt_bit <= r_cnt_bit + 1'b1;
                end
                TA : begin
                    r_shiftreg_ctrl <= r_shiftreg_ctrl;
                    r_shiftreg_data <= r_shiftreg_data;
                    r_read_data     <= 16'd0;
                    r_done          <= 1'b0;
                    if(i_wh_rl == 1'b0)
                        r_mdio_dir <= 1'b0;
                    else begin
                        r_mdio_dir <= 1'b1;
                        r_mdio_out <= (r_cnt_bit==6'd0) ? 1'b1 : 1'b0;
                    end
                    if(r_cnt_bit >= 6'd1)
                        r_cnt_bit <= 6'd0;
                    else
                        r_cnt_bit <= r_cnt_bit + 1'b1;   
                end
                DATA : begin
                    r_shiftreg_ctrl <= 14'd0;
                    r_read_data     <= r_read_data;
                    if(i_wh_rl == 1'b0)
                        r_mdio_dir <= 1'b0;
                    else begin
                        r_mdio_dir <= 1'b1;
                        r_mdio_out <= r_shiftreg_data[15];
                        r_shiftreg_data <= {r_shiftreg_data[14:0],1'b0};
                    end
                    if(r_cnt_bit >= 6'd15) begin
                        r_cnt_bit <= 6'd0;
                        r_done <= 1'b1;
                    end
                    else
                        r_cnt_bit <= r_cnt_bit + 1'b1;  
                end
                default : begin
                    r_mdio_dir      <= r_mdio_dir;     
                    r_cnt_bit       <= r_cnt_bit;      
                    r_mdio_out      <= r_mdio_out;     
                    r_shiftreg_ctrl <= r_shiftreg_ctrl;
                    r_shiftreg_data <= r_shiftreg_data;
                    r_read_data     <= r_read_data;    
                end
            endcase
        end
        
        if(r_mdc_rise) begin
            if(r_cur_state == DATA && i_wh_rl == 1'b0) begin
                r_shiftreg_data <= {r_shiftreg_data[14:0],w_mdio_in};
                if(r_cnt_bit == 6'd15)
                    r_read_data <= {r_shiftreg_data[14:0],w_mdio_in};
            end
        end
    end
end


endmodule