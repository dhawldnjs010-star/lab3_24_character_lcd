// LAB3-24 · 문자 LCD 제어 자기검사 테스트벤치
// 출처: 06.LAB3_06_CHARACTER_LCD_VIVADO.pdf (tb_character_lcd.sv, 18~20쪽) 의
// 동작을 simulation.json이 지정한 module 이름(tb_character_lcd)으로 이식.
// Enable 하강 에지에서 초기화 명령과 두 줄 데이터, 총 40바이트의 순서와 RS를 검사한다.
`timescale 1ns/1ps
module tb_character_lcd;
    reg clk_50mhz = 0;
    reg rst_p     = 1;
    wire lcd_e, lcd_rs, lcd_rw;
    wire [7:0] lcd_data;

    reg [7:0] expected_data [0:39];
    reg       expected_rs   [0:39];
    integer   count = 0;
    integer   i;

    always #10 clk_50mhz = ~clk_50mhz;

    // 실제 ms 단위 딜레이 대신 축소한 파라미터를 사용해 시뮬레이션을 빠르게 끝낸다.
    lab3_character_lcd #(
        .TICK_CYCLES(2),
        .POWER_TICKS(3),
        .NORMAL_WAIT_TICKS(1),
        .CLEAR_WAIT_TICKS(2)
    ) dut (
        .clk_50mhz(clk_50mhz),
        .rst_p(rst_p),
        .lcd_e(lcd_e),
        .lcd_rs(lcd_rs),
        .lcd_rw(lcd_rw),
        .lcd_data(lcd_data)
    );

    initial begin
        // 0,1,2: Function Set 0x38 x3 / 3: Display ON 0x0c / 4: Entry Mode 0x06
        // 5: Clear 0x01 / 6: DDRAM 0x80 (1행)
        expected_data[0] = 8'h38; expected_data[1] = 8'h38; expected_data[2] = 8'h38;
        expected_data[3] = 8'h0c; expected_data[4] = 8'h06; expected_data[5] = 8'h01;
        expected_data[6] = 8'h80;
        // 7~15: "FPGA LAB3"
        expected_data[7]  = "F"; expected_data[8]  = "P"; expected_data[9]  = "G";
        expected_data[10] = "A"; expected_data[11] = " "; expected_data[12] = "L";
        expected_data[13] = "A"; expected_data[14] = "B"; expected_data[15] = "3";
        // 16~22: 1행을 16자로 채우는 공백
        for (i = 16; i < 23; i = i + 1)
            expected_data[i] = " ";
        // 23: DDRAM 0xC0 (2행)
        expected_data[23] = 8'hc0;
        // 24~39: "LCD CONTROLLER  "
        expected_data[24] = "L"; expected_data[25] = "C"; expected_data[26] = "D";
        expected_data[27] = " "; expected_data[28] = "C"; expected_data[29] = "O";
        expected_data[30] = "N"; expected_data[31] = "T"; expected_data[32] = "R";
        expected_data[33] = "O"; expected_data[34] = "L"; expected_data[35] = "L";
        expected_data[36] = "E"; expected_data[37] = "R"; expected_data[38] = " ";
        expected_data[39] = " ";

        // RS=0(명령): index 0~6, 23 / RS=1(데이터): 그 외
        for (i = 0; i < 40; i = i + 1)
            expected_rs[i] = (i >= 7 && i != 23);
    end

    // Enable 하강 에지에서 RS·DATA(그리고 write-only RW=0)를 검사한다.
    always @(negedge lcd_e) begin
        if (!rst_p && count < 40) begin
            if (lcd_rw !== 1'b0 || lcd_rs !== expected_rs[count] ||
                lcd_data !== expected_data[count]) begin
                $fatal(1, "FAIL idx=%0d rw=%b rs(exp=%b got=%b) data(exp=%h got=%h)",
                       count, lcd_rw, expected_rs[count], lcd_rs,
                       expected_data[count], lcd_data);
            end
            $display("PASS: idx=%0d rs=%b data=%h", count, lcd_rs, lcd_data);
            count = count + 1;
            if (count == 40) begin
                $display("LAB3_LCD_PASS bytes=%0d", count);
                $finish;
            end
        end
    end

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_character_lcd);
        repeat (3) @(posedge clk_50mhz);
        rst_p = 0;
    end

    // 확정적 타임아웃: FSM이 멈추거나 개수가 모자라면 $fatal로 실패시킨다.
    initial begin
        #50000;
        $fatal(1, "TIMEOUT: count=%0d", count);
    end
endmodule
