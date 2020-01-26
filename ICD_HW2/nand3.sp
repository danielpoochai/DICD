.Title	NAND3
.include	'mosistsmc180.sp'

VDD	vdd!	0	dc	2.0v
VSS	gnd!	0	dc	0v

.param	SUPPLY=2.0
*.options 	scale=90n
.options	post

.tran	0.1ps	1ns
.temp	25

V1	in_a	gnd!	pwl	0ps 0v	100ps	0v	150ps	2.0v	1ns	2.0v		
V2	in_b	gnd!	pwl	0ps	0v	100ps	0v	150ps	2.0v	1ns	2.0v
V3	in_c	gnd!	pwl	0ps	0v	100ps	0v	150ps	2.0v	1ns	2.0v	
M1	output	in_a	vdd!	vdd!	PMOS
+	W=1440n	L=360n
M2	output	in_b	vdd!	vdd!	PMOS
+	W=1440n	L=360n
M3	output	in_c	vdd!	vdd!	PMOS
+	W=1440n	L=360n
M4	output	in_a	output_s	gnd!	NMOS
+	W=2160n	L=360n
M5	output_s	in_b	output_t	gnd!	NMOS
+	W=2160n	L=360n	
M6	output_t	in_c	gnd!	gnd!	NMOS
+	W=2160n	L=360n

.end