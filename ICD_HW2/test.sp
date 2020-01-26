.option post accurate nomod brief
.option post_version=9007
.option runlvl = 5
.op
*simulate post
Vin in gnd pwl 0ps 0 100ps 0 150ps 1.0 1ns 1.0
R1 in out 2k
C1 out gnd 100f
*stumulus
.tran 20ps 1ns
.plot v(in) v(out)
.end