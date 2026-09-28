module led_flow (
    output wire [7:0] led
);

    // 1. 内部振荡器：标称 210 MHz / 4 = 52.5 MHz
    wire clk;

    OSCA osc_inst (
        .OSCOUT(clk),
        .OSCEN(1'b1)
    );

    defparam osc_inst.FREQ_DIV = 4;

    // 2. 配置完成后的初始状态
    reg [24:0] counter = 25'd0;
    reg [7:0] led_state = 8'b0000_0001;

    // 3. 每数满 26,250,000 个时钟，切换到下一颗灯
    always @(posedge clk) begin
        if (counter == 25'd26_249_999) begin
            counter <= 25'd0;
            led_state <= {led_state[6:0], led_state[7]};
        end
        else begin
            counter <= counter + 25'd1;
        end
    end

    // 4. LED 低电平点亮，所以将内部状态取反后输出
    assign led = ~led_state;

endmodule