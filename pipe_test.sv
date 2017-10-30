`timescale 1ns/1ns

module pipe_test (
	input clock, 
	input reset,

	input ready,
	output valid,
	output startofpacket,
	output endofpacket,
	output logic [23:0] data	
);

logic [23:0] data_inner;
logic ready_inner, valid_inner, startofpacket_inner, endofpacket_inner;

gen_interlaced gil (
	.clock 						(clock					),
	.reset 						(reset					),
	.aso_out0_data 				(data_inner				),
	.aso_out0_ready 			(ready_inner			),
	.aso_out0_valid 			(valid_inner			),
	.aso_out0_startofpacket 	(startofpacket_inner	),
	.aso_out0_endofpacket 		(endofpacket_inner		)
);

pipe pip (
	.clock             (clock),
	.reset             (reset),
	.dout_data         (data),
	.dout_ready        (ready),
	.dout_valid        (valid),
	.dout_startofpacket(startofpacket),
	.dout_endofpacket  (endofpacket),
	.din_data          (data_inner),
	.din_ready         (ready_inner),
	.din_valid         (valid_inner),
	.din_startofpacket (startofpacket_inner),
	.din_endofpacket   (endofpacket_inner)
);

endmodule