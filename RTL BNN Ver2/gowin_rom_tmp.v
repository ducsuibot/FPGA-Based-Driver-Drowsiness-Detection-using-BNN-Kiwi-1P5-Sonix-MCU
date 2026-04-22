//Copyright (C)2014-2026 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.12.02_SP1 (64-bit)
//IP Version: 1.0
//Part Number: GW1N-LV1P5LQ100C6/I5
//Device: GW1N-1P5
//Created Time: Wed Apr 22 23:44:16 2026

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

    Gowin_ROM your_instance_name(
        .dout(dout), //output [31:0] dout
        .clk(clk), //input clk
        .oce(oce), //input oce
        .ce(ce), //input ce
        .reset(reset), //input reset
        .ad(ad) //input [10:0] ad
    );

//--------Copy end-------------------
