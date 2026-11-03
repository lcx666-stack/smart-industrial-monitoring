/******************************************************************************
//       _              _                   _        
//      / \     _ __   | |   ___     __ _  (_)   ___ 
//     / _ \   | '_ \  | |  / _ \   / _` | | |  / __|
//    / ___ \  | | | | | | | (_) | | (_| | | | | (__ 
//   /_/   \_\ |_| |_| |_|  \___/   \__, | |_|  \___|
//                                  |___/            
*******************************************************************************
File name       :
Rev                     : 0.1
Description     : AXI4 Rev2.0 slave interface (with limited function)
|       Author  |       modify date     |       log
 chenglong      2022.05.03                      first version done
 chenglong      2022.05.04                      add write data ch
 chenglong      2022.05.06                      add     OOR function
 chenglong      2022.05.09                      add ZERO-WAIT SRAM BUS, RDATA FIFO, BRESP FIFO

*******************************************************************************
-- (c) Copyright 2011 - 2022 Anlogic, Inc. All rights reserved.
--
-- This file contains confidential and proprietary information
-- of Anlogic, Inc. and is protected under China and
-- international copyright and other intellectual property
-- laws.
--
-- DISCLAIMER
-- This disclaimer is not a license and does not grant any
-- rights to the materials distributed herewith. Except as
-- otherwise provided in a valid license issued to you by
-- Anlogic, and to the maximum extent permitted by applicable
-- law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
-- WITH ALL FAULTS, AND ANLOGIC HEREBY DISCLAIMS ALL WARRANTIES
-- AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
-- BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
-- INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
-- (2) Anlogic shall not be liable (whether in contract or tort,
-- including negligence, or under any other theory of
-- liability) for any loss or damage of any kind or nature
-- related to, arising under or in connection with these
-- materials, including for any direct, or any indirect,
-- special, incidental, or consequential loss or damage
-- (including loss of data, profits, goodwill, or any type of
-- loss or damage suffered as a result of any action brought
-- by a third party) even if such damage or loss was
-- reasonably foreseeable or Anlogic had been advised of the
-- possibility of the same.
--
-- CRITICAL APPLICATIONS
-- Anlogic products are not designed or intended to be fail-
-- safe, or for use in any application requiring fail-safe
-- performance, such as life-support or safety devices or
-- systems, Class III medical devices, nuclear facilities,
-- applications related to the deployment of airbags, or any
-- other applications that could lead to death, personal
-- injury, or severe property or environmental damage
-- (individually and collectively, "Critical
-- Applications"). Customer assumes the sole risk and
-- liability of any use of Anlogic products in Critical
-- Applications, subject only to applicable laws and
-- regulations governing limitations on product liability.
--
-- THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
-- PART OF THIS FILE AT ALL TIMES.
*******************************************************************************/

module axi_eram_controller_system_AXI_ERAM_Controller_0 # 
(
//AXI ID   WIDTH
parameter  AXI_ID_WIDTH        = 8,   
//AXI DATA WIDTH
parameter  AXI_DATA_WIDTH      = 64,   
//AXI ADDR WIDTH, allow max memory size is (2**AXI_ADDR_WIDTH) bits
parameter  AXI_ADDR_WIDTH      = 32,   
//out of range error enable
parameter  OOR_ERR_EN          = 1,        
//actual memory size,default is the max memory size
parameter  MEM_SIZE_KB         = (1 << (AXI_ADDR_WIDTH-10))   //parameter default width is 32,if larger than 32,should be 64'hxxxx
)
(
          awid,
          awaddr,
          awlen,
          awsize,
          awburst,
          awlock,
          awvalid,
          awready,
          wdata,
          wstrb,
          wvalid,
          wready,
          bid,
          bresp,
          bvalid,
          bready,
          arid,
          araddr,
          arlen,
          arsize,
          arburst,
          arlock,
          arvalid,
          arready,
          rid,
          rdata,
          rresp,
          rlast,
          rvalid,
          rready,
          mem_addr,
          mem_web,
          mem_csb,
          mem_din,
          mem_dout,
          aclk,
          aresetn
);

localparam SLAVE_MSB       = AXI_ADDR_WIDTH-1;
localparam MEM_ADDR_LSB    = tgeeam(AXI_DATA_WIDTH/8); 
localparam MEM_ADDR_MSB    = SLAVE_MSB;           
localparam MEM_ADDR_WIDTH  = MEM_ADDR_MSB - MEM_ADDR_LSB + 1;

//AXI Signals
input         [AXI_ID_WIDTH-1:0] awid;
input          [AXI_ADDR_WIDTH-1:0] awaddr;
input                  [7:0] awlen;
input                  [2:0] awsize;
input                  [1:0] awburst;
input                        awlock;
input                        awvalid;
output                       awready;

input       [AXI_DATA_WIDTH-1:0] wdata;
input   [(AXI_DATA_WIDTH/8)-1:0] wstrb;
input                        wvalid;
output                       wready;

output        [AXI_ID_WIDTH-1:0] bid;
output                 [1:0] bresp;
output                       bvalid;
input                        bready;

input         [AXI_ID_WIDTH-1:0] arid;
input          [AXI_ADDR_WIDTH-1:0] araddr;
input                  [7:0] arlen;
input                  [2:0] arsize;
input                  [1:0] arburst;
input                        arlock;
input                        arvalid;
output                       arready;

output        [AXI_ID_WIDTH-1:0] rid;
output      [AXI_DATA_WIDTH-1:0] rdata;
output                 [1:0] rresp;
output                       rlast;
output                       rvalid;
input                        rready;
//Memory signals
output  [MEM_ADDR_WIDTH-1:0] mem_addr;    //tmldcq address
output  [(AXI_DATA_WIDTH/8)-1:0] mem_web;     //any bit is 0: write cycle,   all bit is 1: read cycle
output                       mem_csb;     //select signal 
output      [AXI_DATA_WIDTH-1:0] mem_din;     //tmldcq data in,onlt 8/16/32/64/128/256/512/1024
input       [AXI_DATA_WIDTH-1:0] mem_dout;    //tmldcq data out

input                        aclk;
input                        aresetn;

`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "Anlogic"
`pragma protect encrypt_agent_info = "Anlogic Encryption Tool anlogic_2019"
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
b9eIw/SMKFlbEJElLAm4haEyMwMVKrauek7KT1OLGSskrfKqUk5Gr6l42EnuTs96
eXyv0tW4fh4i7pUbsegsjfZCnq2KwLlrq86LTOS5QI87+JbvIDc+gwdSlKNZF7W3
2Vyc9rp9Mpnt1pVrqxHBtSHofNO783bfyM5WSquMRMM=
`pragma protect key_keyowner = "Synopsys", key_keyname = "SNPS-VCS-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
OhQd+7NF8cE4fURNw7fw2gP4AWDM+qQSoVhcOAnAdx1/QB7Pc+dqhQS2F94V/ti7
itnBXE+V4HrJrj/E6IHniVakgJylxk8gRjYR/ZexcOodwyvW4SKWgsD53ELjn4W6
YQXNAIuZWIZ1yD0nGC9rVu8uz1gAV0hd0L0zwvfG0wI=
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-2"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
jMtncoOPZjlDBa3wOTne2zFc/eA404LlfePFlVdDanf/Z2v41z2uC8I6vkKXZyUE
sousX13rzpKZs95eVCpg0825NInD9jgSE/Qiai5AVd6EHqLSIUDKZIfiq5pIomHU
1T72YQWjG6+KPCeAueG1hDEKjoYADAQwcxwdolvg8FfrckdEGXB7XWCxq1MJskBt
MoDoG3N2Chxe8Pt9JXl7cBZ4m8WHoTjeGLyZOTbyJHdiymQmNCwPyN7jLYKpD9W5
CBsOkgU6jJK5hyn5J3QAo8qCje1v1nfbE9TsMTXI7jFmQ1zHfvytLEkdCUWTWFcS
HSqp8sHKKj30XMVrAv1feg==
`pragma protect key_keyowner = "Mentor Graphics Corporation", key_keyname = "MGC-VERIF-SIM-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
nW6+ihVzfoQpkFBxnXVeI3eCD3Zf6aPpmhrYGTMke41MAVrlnF7NGDBrYKpve7KS
joaaLg304yBlr09It1MVsa7x5hoR+uyXGuznPhvKsKs920QmYkw9XR31Q3l61IkG
ENFp43G+bt1/Lj+IkhdYaMsFaL9IYyVCZalxXxTFwUw=
`pragma protect key_keyowner = "Cadence Design Systems.", key_keyname = "CDS_RSA_KEY_VER_1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
cbmGg1yiqOzlZTbVYXLPLT6/vDNIzKdVp+cAXtzKATDo1qqPwsZZwW0K08GnpHNT
kqMSXqNu+ko28KGe4/sz6sbJLpYb1A6KUDaUqNaPRdXjm7sM1Q2m5/bp+ofaSRuP
03CfrVX3boFCUrS1MO1nGE7YgIAuJ0aS5G/9looGyoDqhd3rv7ZSD7+sd9SQwj/V
RaJLHt9uMopUhuQSZXdEfyfZYrAIEZO2XOhN4XnqJxyF+nDEkRAGujDfuBijoPK9
ndy0ADQfU1qYjlUKaNypJm4GToUJPFmGyVC+w0x8cu6r384kBquCmQIzXjGkiBi/
D3298voH7toy5EheRhvEFQ==
`pragma protect key_keyowner = "Anlogic", key_keyname = "anlogic-rsa-008"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
goGxqcPo8eFPz1k9ip2o1P7jrtOZnQl8Yu1WXrlVlTrLq9thvHfKUO5fzczCpIho
tn3xkZEctgZo+ICX3dhgFv4rSOVqaVC3Ue76G5oGaIW45LVn/gW/dLKir/QE6xXk
fHbu9IZFPwA7VVJPvfnavpXE9GezeL4KUVz0ag1Rlcg=
`pragma protect key_keyowner = "Anlogic", key_keyname = "anlogic-rsa-009"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 128)
`pragma protect key_block
NxqCKW1wKktQG0pPnXpNk3F8TFS1rfXsqQS56eWnGTZboT3wwT0wSEuDA6meLi1K
TSh/bCGcehADrWZpf+hwpYL6EPwspsEywCAylg+neM4GzPZPrQCA0K2FB57ZVsTV
29FI2jbBr3ajpp+zSikXSfFDX5Sux3n9qdRNm4MsIdQ=
`pragma protect key_keyowner = "Univista", key_keyname = "UV-ENC-RSA-1"
`pragma protect key_method = "rsa"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 256)
`pragma protect key_block
gUMhcmZD892QogbWoleqEXo1e1TE5irKQE4n+hPLumLh6zgpRqF0P0jfiBAFLITL
Rvu7Bpab84HpGklwehV/h4yNNGtAOCKvWfv4ycyY7Hns9Dmkw6B8+fGVSfx4kbae
o2vkKydk1uswZUiHMEbZpi8d58RuWnaiD+jrmmJy3RPQswut/P39sx5WbkMCefWs
sJXtE73AHHP3ayUuaKTnRVtn/x2zfg6wiJRqG/lOLNtkM0m26/RYx71BCEMk1o9T
jG3F93gXfKoxTKEpflcsigTyH94bnutjfJh8NIVeCR0IcpQYeAT111FA/5qFfPvI
SsoFvnuuwEWZMySRfIsORw==
`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 64, bytes = 27456)
`pragma protect data_block
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
`pragma protect end_protected
endmodule
