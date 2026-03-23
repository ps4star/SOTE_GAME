#+feature dynamic-literals
package muslib
import "base:runtime"
import "core:path/filepath"
import "base:intrinsics"

import "core:fmt"
import "core:slice"

import ma "vendor:miniaudio"

Audio_Spec :: struct {
    channels: int,
    format: ma.format,
    sample_rate: int,
}

Node_Variant_Identity :: struct {}
Node_Variant :: union {
    Node_Variant_Identity,
}

Generic_Node :: struct {
    using base: ma.node_base,
    variant: Node_Variant,
}

Node_Instance :: struct {
    vtable: ma.node_vtable,
    graph_controller: ^Graph_Controller,
    channels_in_table, channels_out_table: [^]u32,
    config: ma.node_config,
    node: Generic_Node,
}

node_proc_identity :: proc "c" (pNode: ^ma.node, ppFramesIn: ^[^]f32, pFrameCountIn: ^u32, ppFramesOut: ^[^]f32, pFrameCountOut: ^u32) {
    // node := transmute(^Generic_Node) pNode
    intrinsics.mem_copy(rawptr(ppFramesOut^), rawptr(ppFramesIn^), int(pFrameCountIn^))
    pFrameCountOut^ = pFrameCountIn^
}

node_prototypes := map[string]Node_Instance{
    "identity" = {
        vtable = {
            onProcess = node_proc_identity,
            onGetRequiredInputFrameCount = nil,
            inputBusCount = 1,
            outputBusCount = 1,
            flags = {},
        },
    },
}

register_node_prototype :: proc(key: string, data: Node_Instance) {
    assert(key not_in node_prototypes) // Avoid collisions
    node_prototypes[key] = data
}

Graph :: struct {
    node_graph: ma.node_graph,
    instances: map[string]Node_Instance,
}
GRAPH_INDEX_STARTPOINT :: 0
GRAPH_INDEX_ENDPOINT :: -1

Graph_Controller :: struct {
    graph_resource_allocator: runtime.Allocator,
    audio_spec: Audio_Spec,
    node_graph_config: ma.node_graph_config,
    graphs: map[string]Graph,
}

graph_controller_init :: proc(this: ^Graph_Controller, audio_spec: Audio_Spec, graph_resource_allocator := context.allocator) {
    this.graph_resource_allocator = graph_resource_allocator
    this.audio_spec = audio_spec
    this.node_graph_config = ma.node_graph_config_init(u32(this.audio_spec.channels))
    this.graphs = make(map[string]Graph, 1024, this.graph_resource_allocator)
}

graph_controller_create_graph :: proc(this: ^Graph_Controller, name: string) {
    this.graphs[name] = Graph{}
    graph := &this.graphs[name]
    ma.node_graph_init(&this.node_graph_config, nil, &graph.node_graph)

    graph.instances = make(map[string]Node_Instance, 1024, this.graph_resource_allocator)
}

graph_controller_get_graph_ptr_by_name :: proc(this: ^Graph_Controller, name: string) -> (^Graph) {
    _, ok := this.graphs[name]
    if !ok {
        return nil
    }
    return &this.graphs[name]
}

graph_controller_add_node_to_graph :: proc(this: ^Graph_Controller, graph_name, node_name, prototype: string) -> (^Node_Instance) {
    if (prototype not_in node_prototypes) {
        panic(fmt.tprintf("No such name:", prototype, "registered in node prototypes map"))
    }

    graph_ptr := graph_controller_get_graph_ptr_by_name(this, graph_name); assert(graph_ptr != nil)
    graph_ptr.instances[node_name] = node_prototypes[prototype]
    proto := &graph_ptr.instances[node_name]

    in_slice := make([]u32, proto.vtable.inputBusCount, this.graph_resource_allocator); slice.fill(in_slice, u32(this.audio_spec.channels))
    proto.channels_in_table = raw_data(in_slice)
    out_slice := make([]u32, proto.vtable.outputBusCount, this.graph_resource_allocator); slice.fill(out_slice, u32(this.audio_spec.channels))
    proto.channels_out_table = raw_data(out_slice)

    proto.config = ma.node_config_init()
    proto.config.vtable = &proto.vtable
    proto.config.pInputChannels = proto.channels_in_table
    proto.config.pOutputChannels = proto.channels_out_table
    proto.graph_controller = this

    ma.node_init(&graph_ptr.node_graph, &proto.config, nil, transmute(^ma.node) &proto.node)
    return proto
}

ENDPOINT_NODE :: "__ENDPOINT__"
graph_controller_link_nodes :: proc(this: ^Graph_Controller, graph_name, a, b: string, a_bus, b_bus: int) {
    assert(this != nil)
    graph_ptr := graph_controller_get_graph_ptr_by_name(this, graph_name); assert(graph_ptr != nil)

    assert(a != ENDPOINT_NODE && a in graph_ptr.instances)
    assert(b in graph_ptr.instances || b == ENDPOINT_NODE)

    a_inst_ptr, b_inst_ptr: ^Node_Instance; a_node_ptr, b_node_ptr: ^ma.node
    a_inst_ptr = &graph_ptr.instances[a]
    a_node_ptr = transmute(^ma.node) &a_inst_ptr.node
    
    if b == ENDPOINT_NODE {
        b_node_ptr = ma.node_graph_get_endpoint(&graph_ptr.node_graph)
    } else {
        b_inst_ptr = &graph_ptr.instances[b]
        b_node_ptr = transmute(^ma.node) &b_inst_ptr.node
    }
    ma.node_attach_output_bus(a_node_ptr, u32(a_bus), b_node_ptr, u32(b_bus))
}

// The spec of pcm_frames is implied by <Graph_Controller>.audio_spec
graph_controller_graph_read_pcm_frames :: proc(this: ^Graph_Controller, graph_name: string, out: $T/[]$E, frame_count: int)
    where   intrinsics.type_is_numeric(E),
            intrinsics.type_is_slice(T)
{
    graph_ptr := graph_controller_get_graph_ptr_by_name(this, graph_name); assert(graph_ptr != nil)
    frames_read: u64
    res := ma.node_graph_read_pcm_frames(&graph_ptr.node_graph, raw_data(out), u64(frame_count), &frames_read); assert(res == .SUCCESS)
}