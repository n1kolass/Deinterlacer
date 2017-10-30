`timescale 1ns/1ns

module structure (
	input         		clock,
	input        		reset,
	input  logic   		dout_ready,
	output logic [7:0] dout_data,
	output logic 		dout_valid,
	output logic 		dout_startofpacket,
	output logic 		dout_endofpacket//,
	// output logic [23:0] ref_dout_data,
	// output logic 		ref_dout_valid,
	// output logic 		ref_dout_startofpacket,
	// output logic 		ref_dout_endofpacket
);

logic [15:0] data;		// gen:aso_out0_data -> dil:din_data
logic valid;			// gen:aso_out0_valid -> dil:din_valid
logic startofpacket;	// gen:aso_out0_startofpacket -> dil:din_startofpacket
logic endofpacket;		// gen:aso_out0_endofpacket -> dil:din_endofpacket
logic ready;			// dil:din_ready -> gen:aso_out0_ready

gen_interlaced_16b gen (
	.clock					( clock 				),                  
	.reset					( reset 				),                  
	.aso_out0_data			( data 					),          
	.aso_out0_ready			( ready	 				),
	.aso_out0_valid			( valid 				),
	.aso_out0_startofpacket	( startofpacket 		),
    .aso_out0_endofpacket	( endofpacket 			)
);

// generator gen_ref (
// 	.clock					( clock 				),                  
// 	.reset					( reset 				),                  
// 	.aso_out0_data			( ref_dout_data			),          
// 	.aso_out0_ready			( dout_ready			),
// 	.aso_out0_valid			( ref_dout_valid 		),
// 	.aso_out0_startofpacket	( ref_dout_startofpacket),
//     .aso_out0_endofpacket	( ref_dout_endofpacket 	)
// );

deinterlacer_v3 dil (
	.clock					( clock 				),                  
	.reset					( reset 				),
	// AST Source       
	.dout_data				( dout_data 			),
	.dout_ready				( dout_ready 			),
	.dout_valid				( dout_valid 			),
	.dout_startofpacket		( dout_startofpacket 	), 
	.dout_endofpacket		( dout_endofpacket 		),    
	// AST Sink
	.din_data				( data 					),
	.din_ready				( ready 				),
	.din_valid				( valid 				),
	.din_startofpacket		( startofpacket 		),
	.din_endofpacket		( endofpacket 			)
);

endmodule