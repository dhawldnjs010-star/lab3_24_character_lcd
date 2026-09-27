# LAB3-24 · 문자 LCD 제어 — 실험 전 레포트

- 학번/이름: 2025440084 상혁
- 설계 top 모듈: `lab3_character_lcd`
- 도구: Icarus Verilog(iverilog/vvp), `python3 tools/fpga_lab.py simulate`
- 참고 교안: `06.LAB3_06_CHARACTER_LCD_VIVADO.pdf` (LAB3-24, Vivado 2026.1, FPGA Part xc7s75fgga484-1)

## 1. 회로 목적

HD44780 호환 문자 LCD를 **8비트 write-only 방식**으로 초기화하고, 16x2 LCD의 1행에
`FPGA LAB3`, 2행에 `LCD CONTROLLER`를 표시한다. MCU 쪽에서 LCD의 상태(Busy Flag)를
읽지 않고(RW=0 고정), 각 명령·데이터 전송 뒤 데이터시트가 보장하는 최대 실행 시간만큼
고정 딜레이로 기다리는 open-loop 방식이다. 최상위 입력은 `clk_50mhz`(50MHz) 하나뿐이며,
모든 느린 타이밍은 이 클록에서 만든 clock-enable(`tick`)로 제어한다.

## 2. 블록 흐름

```
clk_50mhz, rst_p
   │
   ▼
[tick 발생기]  TICK_CYCLES 클록마다 1클록 폭의 tick 펄스 생성
   │ tick
   ▼
[전원 안정화 카운터]  POWER_TICKS 동안 lcd_e=0 유지 (LCD Vcc 안정화 대기)
   │ (경과 후)
   ▼
[명령/데이터 ROM]  index(0~39) → (byte_rs, byte_data) 조합 출력
   │
   ▼
[쓰기 FSM: phase 0→1→2→wait]
   0: lcd_rs/lcd_data 래치           (Address setup)
   1: lcd_e ← 1                       (Enable pulse high)
   2: lcd_e ← 0, wait_count 설정      (Enable pulse low, 명령별 대기 시작)
   wait: wait_count-- 후 0이면 index++ (Data hold / 명령 실행 대기)
   │
   ▼
lcd_rs, lcd_rw(=0 고정), lcd_data[7:0], lcd_e  → LCD 모듈
```

index가 39에 도달하면 6으로 되돌아가 1행 주소 설정(0x80)부터 문자열 쓰기를
무한히 반복한다(초기화 0~5는 1회만 수행).

## 3. 파라미터 계산

설계 기본 파라미터(`TICK_CYCLES=500, POWER_TICKS=2_000, NORMAL_WAIT_TICKS=4,
CLEAR_WAIT_TICKS=200`)를 clk_50mhz 주기 20 ns 기준으로 환산하면:

| 파라미터 | 값 | 실제 시간 (× tick 주기) | 근거 |
|---|---|---|---|
| tick 주기 | `TICK_CYCLES=500` | 500 × 20 ns = **10 μs/tick** | clock-enable 분주 |
| 전원 안정화 대기 | `POWER_TICKS=2_000` | 2,000 × 10 μs = **20 ms** | HD44780 전원 인가 후 권장 대기(≥15 ms)에 여유 반영 |
| 일반 명령/데이터 대기 | `NORMAL_WAIT_TICKS=4` | 4 × 10 μs = **40 μs** | 대부분의 HD44780 명령 실행 시간(약 37~43 μs)을 충분히 커버 |
| Clear Display 대기 | `CLEAR_WAIT_TICKS=200` | 200 × 10 μs = **2 ms** | Clear Display 실행 시간(전형 1.52 ms, 최대 약 1.64 ms)에 여유 반영 |
| `TICK_WIDTH` | `$clog2(TICK_CYCLES)` | 500→9비트 | tick_count 레지스터 폭 자동 계산 |

시뮬레이션에서는 실제 ms 단위 딜레이를 그대로 쓰면 실행이 느려지므로, TB에서
파라미터를 **비율은 유지한 채** 축소해 인스턴스화했다:

| 파라미터 | 시뮬레이션 값 | 비고 |
|---|---|---|
| `TICK_CYCLES` | 2 (→ tick 주기 40 ns) | 최소 분주(2클록 이상 필요) |
| `POWER_TICKS` | 3 (→ 120 ns) | 전원 대기 단계 존재만 검증 |
| `NORMAL_WAIT_TICKS` | 1 (→ 40 ns) | 명령/데이터 대기 단계 존재만 검증 |
| `CLEAR_WAIT_TICKS` | 2 (→ 80 ns) | Clear가 더 긴 대기를 쓰는 구조만 검증 |

실제 시뮬레이션은 `$finish`가 8,130,000 ps(=8.13 μs) 시점에 호출되어, TB의
타임아웃(`#50000` = 50 μs)보다 충분히 빨리 끝났다.

## 4. 상태/타이밍 표 (FSM 상태표)

| phase | 동작 | 다음 조건 |
|---|---|---|
| (전원) `power_count<POWER_TICKS` | `lcd_e=0` 유지, tick마다 `power_count++` | `power_count==POWER_TICKS`가 되면 phase FSM 시작 |
| 0 | `lcd_e<=0; lcd_rs<=byte_rs; lcd_data<=byte_data` (주소/데이터 셋업) | 다음 tick에 phase→1 |
| 1 | `lcd_e<=1` (Enable High, setup/high 구간) | 다음 tick에 phase→2 |
| 2 | `lcd_e<=0` (Enable Low, hold 종료), `wait_count<=(index==5)?CLEAR_WAIT_TICKS:NORMAL_WAIT_TICKS` | 다음 tick에 phase→3(default) |
| 3 (default) | `wait_count>0`이면 `wait_count--`; `0`이면 `index<=(index==39)?6:index+1`, `phase<=0` | 대기 완료 시 다음 바이트로 |

## 5. RTL·TB·XDC 역할 설명

- **`src/lab3_character_lcd.v` (`lab3_character_lcd`)**: 유일한 순차 로직 클록 `clk_50mhz`와 비동기 리셋
  `rst_p`을 받아 ①tick 생성기, ②index→명령/데이터 조합 ROM, ③Enable 펄스 FSM 세 블록으로
  구성. 출력은 `lcd_e, lcd_rs`(reg), `lcd_rw`(0 고정 wire), `lcd_data[7:0]`(reg)이다.
- **`sim/tb_character_lcd.sv` (`tb_character_lcd`)**: DUT(`lab3_character_lcd`)를 축소 파라미터로
  인스턴스화하고, 기대 40바이트(`expected_data[0:39]`)와 기대 RS(`expected_rs[0:39]`)를
  미리 채운 뒤 `lcd_e` 하강 에지마다 `lcd_rw/lcd_rs/lcd_data`를 비교한다. 불일치 시
  `$fatal`, 각 항목 통과 시 `$display("PASS: ...")`, 40개를 모두 통과하면
  `LAB3_LCD_PASS bytes=40`을 출력하고 `$finish`한다. `$dumpfile("wave.vcd")`/`$dumpvars`로
  파형을 남기고, `#50000` 뒤에도 끝나지 않으면 `$fatal`로 확정 종료한다.
- **`constraints/lab3_character_lcd.xdc`**: `lab3_character_lcd`의 top 포트 6개(`clk_50mhz, rst_p, lcd_e,
  lcd_rs, lcd_rw, lcd_data[7:0]`)를 PDF의 핀 표대로 `PACKAGE_PIN`에 매핑하고 전체 포트에
  `IOSTANDARD LVCMOS33`을 지정한다. `create_clock`으로 50 MHz(20 ns) 제약, `rst_p`는
  `set_false_path`로 비동기 리셋임을 명시한다. Icarus 시뮬레이션에는 사용되지 않고
  Vivado 합성/구현 단계에서만 유효하다.

## 6. TB 자극 → 기대 결과 표 (요약, 전체 40바이트 중 대표 구간)

| index | RS | DATA(hex) | 의미 |
|---|---|---|---|
| 0,1,2 | 0 | 0x38 | Function Set (8비트, 2라인) ×3 |
| 3 | 0 | 0x0c | Display ON/OFF (표시 ON, 커서/블링크 OFF) |
| 4 | 0 | 0x06 | Entry Mode Set (주소 증가, 화면 시프트 없음) |
| 5 | 0 | 0x01 | Display Clear (긴 대기 필요) |
| 6 | 0 | 0x80 | DDRAM Address = 1행 시작 |
| 7~15 | 1 | 46,50,47,41,20,4c,41,42,33 | "FPGA LAB3" |
| 16~22 | 1 | 0x20 ×7 | 1행 16자 채움 공백 |
| 23 | 0 | 0xc0 | DDRAM Address = 2행 시작 |
| 24~37 | 1 | "LCD CONTROLLER" | 2행 문자열 |
| 38,39 | 1 | 0x20, 0x20 | 2행 16자 채움 공백 |

## 7. Icarus PASS 결과 핵심 로그

```
$ python3 tools/fpga_lab.py simulate
PASS: idx=0 rs=0 data=38
PASS: idx=1 rs=0 data=38
PASS: idx=2 rs=0 data=38
PASS: idx=3 rs=0 data=0c
PASS: idx=4 rs=0 data=06
PASS: idx=5 rs=0 data=01
PASS: idx=6 rs=0 data=80
PASS: idx=7 rs=1 data=46
...
PASS: idx=38 rs=1 data=20
PASS: idx=39 rs=1 data=20
LAB3_LCD_PASS bytes=40
sim/tb_character_lcd.sv:75: $finish called at 8130000 (1ps)

시뮬레이션 실행 완료. ...
WAVE .../build/sim/wave.vcd
```
`build/sim/result.json`의 `status`는 `SIMULATED`이며, 40개 PASS 메시지와
`LAB3_LCD_PASS bytes=40`을 모두 확인했다(전체 로그: `build/sim/run-*/simulation.log`).

## 8. 한 항목 수정 실험과 복구 결과

| 단계 | 변경 내용 | 결과 | 로그 |
|---|---|---|---|
| 정상 | `src/lab3_character_lcd.v` 59행 `3: byte_data = 8'h0c;` (Display ON/OFF) | PASS 40/40, `LAB3_LCD_PASS bytes=40` | 위 7절 |
| 수정 | `8'h0c` → `8'h0d`로 의도적 오류 주입 (index=3 명령 코드 1비트 오조작) | idx=0~2 PASS 후 idx=3에서 `$fatal` 발생: `FAIL idx=3 rw=0 rs(exp=0 got=0) data(exp=0c got=0d)` (Time: 890000) | `reports/evidence/mod_experiment_fault.log` |
| 복구 | `8'h0d` → `8'h0c`로 원복 | 재실행 시 다시 PASS 40/40, `LAB3_LCD_PASS bytes=40` | `reports/evidence/mod_experiment_recovered.log` |

TB의 기대값(`expected_data[3]=8'h0c`)은 변경하지 않고 RTL만 수정/복구하여, TB가
설계 오류를 독립적으로 검출함을 확인했다.

## 9. 실제 보드 확인 체크리스트 (전원/대비 연결 포함)

- [ ] 전원을 끈 상태에서 LCD 모듈과 보드의 배선·공통 GND를 먼저 확인한다.
- [ ] LCD의 **Vcc/GND(5V 또는 3.3V, 모듈 사양 확인)** 연결과 **V0(대비, contrast)** 핀이
      가변저항 등으로 적절한 전압에 연결되어 있는지 확인한다(대비 미조정 시 문자가 전혀
      안 보일 수 있음).
- [ ] `lcd_rw`는 0(Write)로 고정 배선되어 있으며 Busy Flag를 읽지 않는 write-only
      구성임을 재확인한다.
- [ ] `pins.xdc`의 `PACKAGE_PIN`이 실제 사용 보드(Combo II-DLD S75)의 핀과 일치하는지
      Vivado의 Open Elaborated Design/I/O Planning에서 대조한다.
- [ ] Reports → Timing → Report Clocks에서 `clk_50mhz` 주기 20.000 ns를 확인한다.
- [ ] Synthesis → Implementation → Generate Bitstream을 순서대로 실행하고, DRC/타이밍
      위반이 없는지 확인한다.
- [ ] Hardware Manager → Open Target → Auto Connect → Program Device로 비트스트림을
      기록하고, 1행 `FPGA LAB3`, 2행 `LCD CONTROLLER` 문자열이 정확히 표시되는지
      확인한다.
- [ ] `rst_p` 버튼 동작 시 화면이 초기화 시퀀스부터 다시 시작하는지 확인한다.
- [ ] 보드 전체 사진과 동작 영상을 촬영해 실험 후 레포트에 첨부한다.

## 10. 핀 표 요약 (신호명 / PACKAGE_PIN / IOSTANDARD)

| 신호명 | PACKAGE_PIN | IOSTANDARD |
|---|---|---|
| `clk_50mhz` | B6 | LVCMOS33 |
| `rst_p` | K4 | LVCMOS33 |
| `lcd_e` | A6 | LVCMOS33 |
| `lcd_rs` | G6 | LVCMOS33 |
| `lcd_rw` | D6 | LVCMOS33 |
| `lcd_data[0]` | A4 | LVCMOS33 |
| `lcd_data[1]` | B2 | LVCMOS33 |
| `lcd_data[2]` | C3 | LVCMOS33 |
| `lcd_data[3]` | D4 | LVCMOS33 |
| `lcd_data[4]` | A2 | LVCMOS33 |
| `lcd_data[5]` | C5 | LVCMOS33 |
| `lcd_data[6]` | C1 | LVCMOS33 |
| `lcd_data[7]` | D1 | LVCMOS33 |

추가 제약: `create_clock -name clk_50mhz -period 20.000 [get_ports clk_50mhz]`,
`set_false_path -from [get_ports rst_p]`.
