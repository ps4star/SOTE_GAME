package muslib

import ma "vendor:miniaudio"

// Put custom nodes here
register_custom_nodes :: proc() {
    when false {
        register_node_prototype("identity_example", Node_Instance{
            vtable = {
                onProcess = node_proc_identity,
                onGetRequiredInputFrameCount = nil,
                inputBusCount = 1,
                outputBusCount = 1,
                flags = {},
            },
        })
    }
}

@(private="package") DEBUG :: #config(DEBUG, false)

// Debug test
when DEBUG {
main :: proc() {
    register_custom_nodes()

    @static gc: Graph_Controller
    graph_controller_init(&gc, { sample_rate = 44100, channels = 2, format = .f32 }, context.allocator)
    graph_controller_create_graph(&gc, "test")
    graph_controller_add_node_to_graph(&gc, graph_name="test", node_name="test0", prototype="identity")
    graph_controller_link_nodes(&gc, graph_name="test", a="test0", b=ENDPOINT_NODE, a_bus=0, b_bus=0)
}
}