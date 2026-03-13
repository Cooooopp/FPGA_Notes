`timescale 1ns / 1ps

module tb_mdio_driver();

    // ==========================================
    // 1. 信号声明 (对应你的模块接口)
    // ==========================================
    reg         clk;           // 100MHz 时钟
    reg         rst_n;         // 复位
    
    wire        mdc;           // 输出的 6.25MHz MDC
    wire        mdio;          // inout 双向总线
    
    reg         i_start;
    reg         i_wh_rl;       // 1:写, 0:读
    reg  [4:0]  i_phy_addr;
    reg  [4:0]  i_reg_addr;
    reg  [15:0] i_write_data;
    wire [15:0] o_read_data;
    wire        o_done;

    // ==========================================
    // 2. 模拟 PHY 芯片的总线驱动逻辑
    // ==========================================
    reg  tb_mdio_dir;       // 1: TB(模拟PHY)驱动总线, 0: 释放总线
    reg  tb_mdio_out;       // TB 准备输出的值
    
    // 三态门：控制模拟的 PHY 芯片是否往线上写数据
    assign mdio = tb_mdio_dir ? tb_mdio_out : 1'bz;

    // 弱上拉电阻模拟 (规范要求 MDIO 空闲时为高电平)
    pullup(mdio);

    // ==========================================
    // 3. 例化你的模块 (DUT)
    // ==========================================
    mdio_driver u_mdio_driver (
        .clk            (clk),
        .rst_n          (rst_n),
        .mdc            (mdc),
        .mdio           (mdio),
        .i_start        (i_start),
        .i_wh_rl        (i_wh_rl),
        .i_phy_addr     (i_phy_addr),
        .i_reg_addr     (i_reg_addr),
        .i_write_data   (i_write_data),
        .o_read_data    (o_read_data),
        .o_done         (o_done)
    );

    // ==========================================
    // 4. 时钟生成 (100MHz -> 周期 10ns)
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // ==========================================
    // 5. 辅助任务：等待 N 个 MDC 下降沿
    // ==========================================
    task wait_mdc_falls;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(negedge mdc);
            end
        end
    endtask

    // ==========================================
    // 6. 主测试激励
    // ==========================================
    integer bit_idx;
    reg [15:0] mock_phy_data;

    initial begin
        // --- 初始化 ---
        rst_n        = 0;
        i_start      = 0;
        i_wh_rl      = 0;
        i_phy_addr   = 5'd0;
        i_reg_addr   = 5'd0;
        i_write_data = 16'd0;
        
        tb_mdio_dir  = 0; // 初始状态 PHY 释放总线
        tb_mdio_out  = 1;
        
        #100;
        rst_n = 1;
        #200;

        // -----------------------------------------------------------
        // 测试案例 1：发起一次【写操作】 (i_wh_rl = 1)
        // 目标：PHY=0x01, REG=0x00, DATA=16'h5A5A
        // -----------------------------------------------------------
        $display("[%0t] Starting WRITE Operation...", $time);
        @(posedge clk);
        #2;
        i_start      = 1;
        i_wh_rl      = 1;      // 写
        i_phy_addr   = 5'h01;
        i_reg_addr   = 5'h00;
        i_write_data = 16'h5A5A;
        @(posedge clk);
        #2;
        i_start      = 0;      // start 只有一拍脉冲
        
        // 写操作期间，总线全由 FPGA 控制，TB 只需要挂机等 o_done 即可
        @(posedge o_done);
        $display("[%0t] WRITE Operation Done.", $time);
        
        #2000; // 等待一段时间间隔

        // -----------------------------------------------------------
        // 测试案例 2：发起一次【读操作】 (i_wh_rl = 0)
        // 目标：PHY=0x01, REG=0x01
        // 期望：模拟 PHY 返回数据 16'h8899，看 FPGA 能否正确接收
        // -----------------------------------------------------------
        $display("[%0t] Starting READ Operation...", $time);
        @(posedge clk);
        i_start      = 1;
        i_wh_rl      = 0;      // 读
        i_phy_addr   = 5'h01;
        i_reg_addr   = 5'h01;
        
        @(posedge clk);
        i_start      = 0;
        
        // 【核心交互模拟】：
        // 读操作的前导码(32) + 控制码(14) + TA的第一拍(1) = 47 个 MDC 周期
        // 这 47 拍内总线由 FPGA 控制，或者处于高阻态
        wait_mdc_falls(47);
        
        // 第 47 次下降沿后，进入 TA 的第二拍。按照协议，此时 PHY 必须接管总线并拉低
        tb_mdio_dir = 1; 
        tb_mdio_out = 0;
        @(negedge mdc);
        
        // 随后进入 16 拍的 DATA 阶段，模拟 PHY 在每次 MDC 下降沿送出 1 bit 数据 (MSB 先出)
        mock_phy_data = 16'h8899;
        for (bit_idx = 15; bit_idx >= 0; bit_idx = bit_idx - 1) begin
            tb_mdio_out = mock_phy_data[bit_idx];
            @(negedge mdc);
        end
        
        // 数据发送完毕，模拟 PHY 撒手释放总线
        tb_mdio_dir = 0;
        
        // 等待 FPGA 的状态机宣告完成
        @(posedge o_done);
        $display("[%0t] READ Operation Done. Data Read: 0x%h", $time, o_read_data);
        
        if (o_read_data == 16'h8899)
            $display(">>> SUCCESS: Read Data Matches! <<<");
        else
            $display(">>> ERROR: Read Data Mismatch! <<<");

        #1000;
        $finish;
    end

endmodule