`timescale 1ns/1ns

module pipeline_test ();

logic clock, reset;
logic din_ready, din_valid, dout_ready, dout_valid;
logic [23:0] din_data; 
logic [23:0] dout_data;

altera_avalon_st_pipeline_base pipe (
	.clk (clock),
	.reset (reset),
	.in_ready (din_ready),
	.in_valid (din_valid),
	.in_data (din_data),
	.out_ready (dout_ready),
	.out_valid (dout_valid),
	.out_data (dout_data)
);

generator gen (
	.clock        (clock),
	.reset        (reset),
	.data         (din_data),
	.ready        (din_ready),
	.valid        (din_valid),
	.startofpacket(),
	.endofpacket  ()
);
endmodule