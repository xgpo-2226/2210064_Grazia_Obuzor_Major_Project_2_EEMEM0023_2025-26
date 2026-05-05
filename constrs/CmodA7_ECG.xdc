## Cmod A7 (xc7a35t-1cpg236) - ECG Monitor constraints
## Required config properties - prevents DRC CFGBVS-1 warning
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## 12 MHz system clock (Pin L17)
set_property -dict { PACKAGE_PIN L17 IOSTANDARD LVCMOS33 } [get_ports { sys_clk }];
create_clock -add -name sys_clk_pin -period 83.33 -waveform {0 41.66} [get_ports { sys_clk }];

## UART TX to FTDI USB-UART bridge (Pin J18) (FPGA to PC via FTDI)
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports { usb_tx }];

## Heartbeat LED - green LED1 (Pin A17)
set_property -dict { PACKAGE_PIN A17 IOSTANDARD LVCMOS33 } [get_ports { led }];

## XADC analog inputs VAUX4 (Pins 15/16 on DIP header = G3/G2)
## Analog pins must NOT have IOSTANDARD set - the XADC wizard owns these.
set_property -dict { PACKAGE_PIN G3 } [get_ports { vauxp4 }];
set_property -dict { PACKAGE_PIN G2 } [get_ports { vauxn4 }];
