//! SDL's GPU API: a modern, explicit graphics and compute layer that runs on
//! Vulkan, Metal and D3D12 from one set of calls.
//!
//! The shape of a frame:
//!
//! ```zig
//! const cmd = try device.acquireCommandBuffer();
//! const swapchain = try cmd.waitAndAcquireSwapchainTexture(window);
//! if (swapchain.texture) |target| {
//!     const pass = try cmd.beginRenderPass(&.{.{
//!         .texture = target,
//!         .clear_color = .{ .r = 0.1, .g = 0.1, .b = 0.12, .a = 1 },
//!         .load_op = .clear,
//!         .store_op = .store,
//!     }}, null);
//!     pass.bindGraphicsPipeline(pipeline);
//!     pass.drawPrimitives(3, 1, 0, 0);
//!     pass.end();
//! }
//! try cmd.submit();
//! ```
//!
//! Three rules the API will not enforce for you:
//!
//! 1. A command buffer belongs to the thread that acquired it, and must be
//!    submitted or cancelled from that thread.
//! 2. A swapchain texture is owned by the swapchain. Never release it, and
//!    never use it after the command buffer is submitted.
//! 3. Resources are freed with `device.release*`, and only once the GPU is
//!    done with them. `device.waitForIdle` before a teardown is the blunt
//!    way to be sure.
//!
//! Shaders are backend-specific bytecode: SPIR-V for Vulkan, DXIL for D3D12,
//! MSL or a metallib for Metal. `device.shaderFormats` says which the device
//! took, and there is no cross-compilation here -- ship the formats you need.

const std = @import("std");
const raw = @import("sdl3_raw");
const errors = @import("errors.zig");
const pixels_mod = @import("pixels.zig");
const rect_mod = @import("rect.zig");
const video_mod = @import("video.zig");
const properties_mod = @import("properties.zig");

const Error = errors.Error;
const check = errors.check;
const FColor = pixels_mod.FColor;
const Rect = rect_mod.Rect;
const Window = video_mod.Window;
const Properties = properties_mod.Properties;

// ---------------------------------------------------------------------
// Enums and flags
// ---------------------------------------------------------------------

/// Which shader bytecode formats a device can take. A device is created by
/// asking for the ones you have, and SDL picks a backend that accepts them.
pub const ShaderFormat = packed struct(u32) {
    /// The platform's own opaque format, on the consoles that have one.
    private: bool = false,
    /// Vulkan.
    spirv: bool = false,
    /// D3D12, the older compiler.
    dxbc: bool = false,
    /// D3D12.
    dxil: bool = false,
    /// Metal, as source.
    msl: bool = false,
    /// Metal, precompiled.
    metallib: bool = false,
    _reserved: u26 = 0,
};

pub const ShaderStage = enum(c_uint) {
    vertex = raw.SDL_GPU_SHADERSTAGE_VERTEX,
    fragment = raw.SDL_GPU_SHADERSTAGE_FRAGMENT,
    _,
};

pub const PrimitiveType = enum(c_uint) {
    triangle_list = raw.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
    triangle_strip = raw.SDL_GPU_PRIMITIVETYPE_TRIANGLESTRIP,
    line_list = raw.SDL_GPU_PRIMITIVETYPE_LINELIST,
    line_strip = raw.SDL_GPU_PRIMITIVETYPE_LINESTRIP,
    point_list = raw.SDL_GPU_PRIMITIVETYPE_POINTLIST,
    _,
};

/// What happens to a target's existing contents when a pass begins.
pub const LoadOp = enum(c_uint) {
    /// Keep them. Costs bandwidth on a tiler.
    load = raw.SDL_GPU_LOADOP_LOAD,
    /// Overwrite with the clear colour. Cheapest when you are drawing the
    /// whole target anyway.
    clear = raw.SDL_GPU_LOADOP_CLEAR,
    /// Leave them undefined. Cheapest of all, and only safe when every pixel
    /// is written before it is read.
    dont_care = raw.SDL_GPU_LOADOP_DONT_CARE,
    _,
};

pub const StoreOp = enum(c_uint) {
    store = raw.SDL_GPU_STOREOP_STORE,
    /// Throw the result away: right for a depth buffer nothing reads later.
    dont_care = raw.SDL_GPU_STOREOP_DONT_CARE,
    /// Resolve multisampling into the resolve texture and discard this one.
    resolve = raw.SDL_GPU_STOREOP_RESOLVE,
    resolve_and_store = raw.SDL_GPU_STOREOP_RESOLVE_AND_STORE,
    _,
};

pub const IndexElementSize = enum(c_uint) {
    u16 = raw.SDL_GPU_INDEXELEMENTSIZE_16BIT,
    u32 = raw.SDL_GPU_INDEXELEMENTSIZE_32BIT,
    _,
};

/// Not every format works on every device. Ask `Device.supportsTextureFormat`
/// before relying on one that is not in the guaranteed set.
pub const TextureFormat = enum(c_uint) {
    invalid = raw.SDL_GPU_TEXTUREFORMAT_INVALID,
    a8_unorm = raw.SDL_GPU_TEXTUREFORMAT_A8_UNORM,
    r8_unorm = raw.SDL_GPU_TEXTUREFORMAT_R8_UNORM,
    r8g8_unorm = raw.SDL_GPU_TEXTUREFORMAT_R8G8_UNORM,
    r8g8b8a8_unorm = raw.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
    r16_unorm = raw.SDL_GPU_TEXTUREFORMAT_R16_UNORM,
    r16g16_unorm = raw.SDL_GPU_TEXTUREFORMAT_R16G16_UNORM,
    r16g16b16a16_unorm = raw.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_UNORM,
    r10g10b10a2_unorm = raw.SDL_GPU_TEXTUREFORMAT_R10G10B10A2_UNORM,
    b5g6r5_unorm = raw.SDL_GPU_TEXTUREFORMAT_B5G6R5_UNORM,
    b5g5r5a1_unorm = raw.SDL_GPU_TEXTUREFORMAT_B5G5R5A1_UNORM,
    b4g4r4a4_unorm = raw.SDL_GPU_TEXTUREFORMAT_B4G4R4A4_UNORM,
    b8g8r8a8_unorm = raw.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM,
    bc1_rgba_unorm = raw.SDL_GPU_TEXTUREFORMAT_BC1_RGBA_UNORM,
    bc2_rgba_unorm = raw.SDL_GPU_TEXTUREFORMAT_BC2_RGBA_UNORM,
    bc3_rgba_unorm = raw.SDL_GPU_TEXTUREFORMAT_BC3_RGBA_UNORM,
    bc4_r_unorm = raw.SDL_GPU_TEXTUREFORMAT_BC4_R_UNORM,
    bc5_rg_unorm = raw.SDL_GPU_TEXTUREFORMAT_BC5_RG_UNORM,
    bc7_rgba_unorm = raw.SDL_GPU_TEXTUREFORMAT_BC7_RGBA_UNORM,
    bc6h_rgb_float = raw.SDL_GPU_TEXTUREFORMAT_BC6H_RGB_FLOAT,
    bc6h_rgb_ufloat = raw.SDL_GPU_TEXTUREFORMAT_BC6H_RGB_UFLOAT,
    r8_snorm = raw.SDL_GPU_TEXTUREFORMAT_R8_SNORM,
    r8g8_snorm = raw.SDL_GPU_TEXTUREFORMAT_R8G8_SNORM,
    r8g8b8a8_snorm = raw.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_SNORM,
    r16_snorm = raw.SDL_GPU_TEXTUREFORMAT_R16_SNORM,
    r16g16_snorm = raw.SDL_GPU_TEXTUREFORMAT_R16G16_SNORM,
    r16g16b16a16_snorm = raw.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_SNORM,
    r16_float = raw.SDL_GPU_TEXTUREFORMAT_R16_FLOAT,
    r16g16_float = raw.SDL_GPU_TEXTUREFORMAT_R16G16_FLOAT,
    r16g16b16a16_float = raw.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT,
    r32_float = raw.SDL_GPU_TEXTUREFORMAT_R32_FLOAT,
    r32g32_float = raw.SDL_GPU_TEXTUREFORMAT_R32G32_FLOAT,
    r32g32b32a32_float = raw.SDL_GPU_TEXTUREFORMAT_R32G32B32A32_FLOAT,
    r11g11b10_ufloat = raw.SDL_GPU_TEXTUREFORMAT_R11G11B10_UFLOAT,
    r8_uint = raw.SDL_GPU_TEXTUREFORMAT_R8_UINT,
    r8g8_uint = raw.SDL_GPU_TEXTUREFORMAT_R8G8_UINT,
    r8g8b8a8_uint = raw.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UINT,
    r16_uint = raw.SDL_GPU_TEXTUREFORMAT_R16_UINT,
    r16g16_uint = raw.SDL_GPU_TEXTUREFORMAT_R16G16_UINT,
    r16g16b16a16_uint = raw.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_UINT,
    r32_uint = raw.SDL_GPU_TEXTUREFORMAT_R32_UINT,
    r32g32_uint = raw.SDL_GPU_TEXTUREFORMAT_R32G32_UINT,
    r32g32b32a32_uint = raw.SDL_GPU_TEXTUREFORMAT_R32G32B32A32_UINT,
    r8_int = raw.SDL_GPU_TEXTUREFORMAT_R8_INT,
    r8g8_int = raw.SDL_GPU_TEXTUREFORMAT_R8G8_INT,
    r8g8b8a8_int = raw.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_INT,
    r16_int = raw.SDL_GPU_TEXTUREFORMAT_R16_INT,
    r16g16_int = raw.SDL_GPU_TEXTUREFORMAT_R16G16_INT,
    r16g16b16a16_int = raw.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_INT,
    r32_int = raw.SDL_GPU_TEXTUREFORMAT_R32_INT,
    r32g32_int = raw.SDL_GPU_TEXTUREFORMAT_R32G32_INT,
    r32g32b32a32_int = raw.SDL_GPU_TEXTUREFORMAT_R32G32B32A32_INT,
    r8g8b8a8_unorm_srgb = raw.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM_SRGB,
    b8g8r8a8_unorm_srgb = raw.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM_SRGB,
    bc1_rgba_unorm_srgb = raw.SDL_GPU_TEXTUREFORMAT_BC1_RGBA_UNORM_SRGB,
    bc2_rgba_unorm_srgb = raw.SDL_GPU_TEXTUREFORMAT_BC2_RGBA_UNORM_SRGB,
    bc3_rgba_unorm_srgb = raw.SDL_GPU_TEXTUREFORMAT_BC3_RGBA_UNORM_SRGB,
    bc7_rgba_unorm_srgb = raw.SDL_GPU_TEXTUREFORMAT_BC7_RGBA_UNORM_SRGB,
    d16_unorm = raw.SDL_GPU_TEXTUREFORMAT_D16_UNORM,
    d24_unorm = raw.SDL_GPU_TEXTUREFORMAT_D24_UNORM,
    d32_float = raw.SDL_GPU_TEXTUREFORMAT_D32_FLOAT,
    d24_unorm_s8_uint = raw.SDL_GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT,
    d32_float_s8_uint = raw.SDL_GPU_TEXTUREFORMAT_D32_FLOAT_S8_UINT,
    _,
};

pub const TextureType = enum(c_uint) {
    two_d = raw.SDL_GPU_TEXTURETYPE_2D,
    two_d_array = raw.SDL_GPU_TEXTURETYPE_2D_ARRAY,
    three_d = raw.SDL_GPU_TEXTURETYPE_3D,
    cube = raw.SDL_GPU_TEXTURETYPE_CUBE,
    cube_array = raw.SDL_GPU_TEXTURETYPE_CUBE_ARRAY,
    _,
};

pub const SampleCount = enum(c_uint) {
    x1 = raw.SDL_GPU_SAMPLECOUNT_1,
    x2 = raw.SDL_GPU_SAMPLECOUNT_2,
    x4 = raw.SDL_GPU_SAMPLECOUNT_4,
    x8 = raw.SDL_GPU_SAMPLECOUNT_8,
    _,
};

pub const CubeMapFace = enum(c_uint) {
    positive_x = raw.SDL_GPU_CUBEMAPFACE_POSITIVEX,
    negative_x = raw.SDL_GPU_CUBEMAPFACE_NEGATIVEX,
    positive_y = raw.SDL_GPU_CUBEMAPFACE_POSITIVEY,
    negative_y = raw.SDL_GPU_CUBEMAPFACE_NEGATIVEY,
    positive_z = raw.SDL_GPU_CUBEMAPFACE_POSITIVEZ,
    negative_z = raw.SDL_GPU_CUBEMAPFACE_NEGATIVEZ,
    _,
};

/// How a texture will be used. Ask for only what you need: a texture that is
/// both a sampler source and a storage target constrains the driver more.
pub const TextureUsage = packed struct(u32) {
    sampler: bool = false,
    color_target: bool = false,
    depth_stencil_target: bool = false,
    graphics_storage_read: bool = false,
    compute_storage_read: bool = false,
    compute_storage_write: bool = false,
    compute_storage_simultaneous_read_write: bool = false,
    _reserved: u25 = 0,
};

pub const BufferUsage = packed struct(u32) {
    vertex: bool = false,
    index: bool = false,
    indirect: bool = false,
    graphics_storage_read: bool = false,
    compute_storage_read: bool = false,
    compute_storage_write: bool = false,
    _reserved: u26 = 0,
};

pub const TransferBufferUsage = enum(c_uint) {
    upload = raw.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
    download = raw.SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD,
    _,
};

pub const VertexElementFormat = enum(c_uint) {
    invalid = raw.SDL_GPU_VERTEXELEMENTFORMAT_INVALID,
    int = raw.SDL_GPU_VERTEXELEMENTFORMAT_INT,
    int2 = raw.SDL_GPU_VERTEXELEMENTFORMAT_INT2,
    int3 = raw.SDL_GPU_VERTEXELEMENTFORMAT_INT3,
    int4 = raw.SDL_GPU_VERTEXELEMENTFORMAT_INT4,
    uint = raw.SDL_GPU_VERTEXELEMENTFORMAT_UINT,
    uint2 = raw.SDL_GPU_VERTEXELEMENTFORMAT_UINT2,
    uint3 = raw.SDL_GPU_VERTEXELEMENTFORMAT_UINT3,
    uint4 = raw.SDL_GPU_VERTEXELEMENTFORMAT_UINT4,
    float = raw.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT,
    float2 = raw.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
    float3 = raw.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
    float4 = raw.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
    byte2 = raw.SDL_GPU_VERTEXELEMENTFORMAT_BYTE2,
    byte4 = raw.SDL_GPU_VERTEXELEMENTFORMAT_BYTE4,
    ubyte2 = raw.SDL_GPU_VERTEXELEMENTFORMAT_UBYTE2,
    ubyte4 = raw.SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4,
    byte2_norm = raw.SDL_GPU_VERTEXELEMENTFORMAT_BYTE2_NORM,
    byte4_norm = raw.SDL_GPU_VERTEXELEMENTFORMAT_BYTE4_NORM,
    ubyte2_norm = raw.SDL_GPU_VERTEXELEMENTFORMAT_UBYTE2_NORM,
    ubyte4_norm = raw.SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4_NORM,
    short2 = raw.SDL_GPU_VERTEXELEMENTFORMAT_SHORT2,
    short4 = raw.SDL_GPU_VERTEXELEMENTFORMAT_SHORT4,
    ushort2 = raw.SDL_GPU_VERTEXELEMENTFORMAT_USHORT2,
    ushort4 = raw.SDL_GPU_VERTEXELEMENTFORMAT_USHORT4,
    short2_norm = raw.SDL_GPU_VERTEXELEMENTFORMAT_SHORT2_NORM,
    short4_norm = raw.SDL_GPU_VERTEXELEMENTFORMAT_SHORT4_NORM,
    ushort2_norm = raw.SDL_GPU_VERTEXELEMENTFORMAT_USHORT2_NORM,
    ushort4_norm = raw.SDL_GPU_VERTEXELEMENTFORMAT_USHORT4_NORM,
    half2 = raw.SDL_GPU_VERTEXELEMENTFORMAT_HALF2,
    half4 = raw.SDL_GPU_VERTEXELEMENTFORMAT_HALF4,
    _,
};

pub const VertexInputRate = enum(c_uint) {
    /// Advance once per vertex.
    vertex = raw.SDL_GPU_VERTEXINPUTRATE_VERTEX,
    /// Advance once per instance.
    instance = raw.SDL_GPU_VERTEXINPUTRATE_INSTANCE,
    _,
};

pub const FillMode = enum(c_uint) {
    fill = raw.SDL_GPU_FILLMODE_FILL,
    line = raw.SDL_GPU_FILLMODE_LINE,
    _,
};

pub const CullMode = enum(c_uint) {
    none = raw.SDL_GPU_CULLMODE_NONE,
    front = raw.SDL_GPU_CULLMODE_FRONT,
    back = raw.SDL_GPU_CULLMODE_BACK,
    _,
};

pub const FrontFace = enum(c_uint) {
    counter_clockwise = raw.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
    clockwise = raw.SDL_GPU_FRONTFACE_CLOCKWISE,
    _,
};

pub const CompareOp = enum(c_uint) {
    invalid = raw.SDL_GPU_COMPAREOP_INVALID,
    never = raw.SDL_GPU_COMPAREOP_NEVER,
    less = raw.SDL_GPU_COMPAREOP_LESS,
    equal = raw.SDL_GPU_COMPAREOP_EQUAL,
    less_or_equal = raw.SDL_GPU_COMPAREOP_LESS_OR_EQUAL,
    greater = raw.SDL_GPU_COMPAREOP_GREATER,
    not_equal = raw.SDL_GPU_COMPAREOP_NOT_EQUAL,
    greater_or_equal = raw.SDL_GPU_COMPAREOP_GREATER_OR_EQUAL,
    always = raw.SDL_GPU_COMPAREOP_ALWAYS,
    _,
};

pub const StencilOp = enum(c_uint) {
    invalid = raw.SDL_GPU_STENCILOP_INVALID,
    keep = raw.SDL_GPU_STENCILOP_KEEP,
    zero = raw.SDL_GPU_STENCILOP_ZERO,
    replace = raw.SDL_GPU_STENCILOP_REPLACE,
    increment_and_clamp = raw.SDL_GPU_STENCILOP_INCREMENT_AND_CLAMP,
    decrement_and_clamp = raw.SDL_GPU_STENCILOP_DECREMENT_AND_CLAMP,
    invert = raw.SDL_GPU_STENCILOP_INVERT,
    increment_and_wrap = raw.SDL_GPU_STENCILOP_INCREMENT_AND_WRAP,
    decrement_and_wrap = raw.SDL_GPU_STENCILOP_DECREMENT_AND_WRAP,
    _,
};

pub const BlendOp = enum(c_uint) {
    invalid = raw.SDL_GPU_BLENDOP_INVALID,
    add = raw.SDL_GPU_BLENDOP_ADD,
    subtract = raw.SDL_GPU_BLENDOP_SUBTRACT,
    reverse_subtract = raw.SDL_GPU_BLENDOP_REVERSE_SUBTRACT,
    min = raw.SDL_GPU_BLENDOP_MIN,
    max = raw.SDL_GPU_BLENDOP_MAX,
    _,
};

pub const BlendFactor = enum(c_uint) {
    invalid = raw.SDL_GPU_BLENDFACTOR_INVALID,
    zero = raw.SDL_GPU_BLENDFACTOR_ZERO,
    one = raw.SDL_GPU_BLENDFACTOR_ONE,
    src_color = raw.SDL_GPU_BLENDFACTOR_SRC_COLOR,
    one_minus_src_color = raw.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_COLOR,
    dst_color = raw.SDL_GPU_BLENDFACTOR_DST_COLOR,
    one_minus_dst_color = raw.SDL_GPU_BLENDFACTOR_ONE_MINUS_DST_COLOR,
    src_alpha = raw.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
    one_minus_src_alpha = raw.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
    dst_alpha = raw.SDL_GPU_BLENDFACTOR_DST_ALPHA,
    one_minus_dst_alpha = raw.SDL_GPU_BLENDFACTOR_ONE_MINUS_DST_ALPHA,
    constant_color = raw.SDL_GPU_BLENDFACTOR_CONSTANT_COLOR,
    one_minus_constant_color = raw.SDL_GPU_BLENDFACTOR_ONE_MINUS_CONSTANT_COLOR,
    src_alpha_saturate = raw.SDL_GPU_BLENDFACTOR_SRC_ALPHA_SATURATE,
    _,
};

/// Which channels a colour target write actually touches.
pub const ColorComponent = packed struct(u8) {
    r: bool = false,
    g: bool = false,
    b: bool = false,
    a: bool = false,
    _reserved: u4 = 0,

    pub const all: ColorComponent = .{ .r = true, .g = true, .b = true, .a = true };
    pub const rgb: ColorComponent = .{ .r = true, .g = true, .b = true };
};

pub const Filter = enum(c_uint) {
    nearest = raw.SDL_GPU_FILTER_NEAREST,
    linear = raw.SDL_GPU_FILTER_LINEAR,
    _,
};

pub const SamplerMipmapMode = enum(c_uint) {
    nearest = raw.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
    linear = raw.SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
    _,
};

pub const SamplerAddressMode = enum(c_uint) {
    repeat = raw.SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
    mirrored_repeat = raw.SDL_GPU_SAMPLERADDRESSMODE_MIRRORED_REPEAT,
    clamp_to_edge = raw.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
    _,
};

pub const PresentMode = enum(c_uint) {
    /// Wait for the refresh. Always supported.
    vsync = raw.SDL_GPU_PRESENTMODE_VSYNC,
    /// Never wait; tears. Check `Device.supportsPresentMode` first.
    immediate = raw.SDL_GPU_PRESENTMODE_IMMEDIATE,
    /// Never wait, never tear, at the cost of a third buffer. Check first.
    mailbox = raw.SDL_GPU_PRESENTMODE_MAILBOX,
    _,
};

pub const SwapchainComposition = enum(c_uint) {
    sdr = raw.SDL_GPU_SWAPCHAINCOMPOSITION_SDR,
    sdr_linear = raw.SDL_GPU_SWAPCHAINCOMPOSITION_SDR_LINEAR,
    hdr_extended_linear = raw.SDL_GPU_SWAPCHAINCOMPOSITION_HDR_EXTENDED_LINEAR,
    hdr10_st2084 = raw.SDL_GPU_SWAPCHAINCOMPOSITION_HDR10_ST2084,
    _,
};

// ---------------------------------------------------------------------
// Handles
// ---------------------------------------------------------------------
//
// These are `opaque` types used through pointers, not structs wrapping a
// pointer like `Window` and `Renderer` are. The reason is layout: the
// create-info structs below hold `?*Texture` and `?*Buffer` fields that SDL
// reads as plain C pointers, and only a real pointer type is guaranteed to
// survive being made optional without growing a tag byte.

// The handle types themselves are at the end of the file, where their
// methods can refer to the plain-data types below.

// ---------------------------------------------------------------------
// Plain data
// ---------------------------------------------------------------------
//
// Each of these is layout-compatible with the SDL struct of the same name;
// the `comptime` block at the end of the file checks every one.

pub const Viewport = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,
    min_depth: f32 = 0,
    max_depth: f32 = 1,
};

pub const TextureTransferInfo = extern struct {
    transfer_buffer: ?*TransferBuffer = null,
    offset: u32 = 0,
    /// 0 means "tightly packed", which is what a plain image buffer is.
    pixels_per_row: u32 = 0,
    rows_per_layer: u32 = 0,
};

pub const TransferBufferLocation = extern struct {
    transfer_buffer: ?*TransferBuffer = null,
    offset: u32 = 0,
};

pub const TextureLocation = extern struct {
    texture: ?*Texture = null,
    mip_level: u32 = 0,
    layer: u32 = 0,
    x: u32 = 0,
    y: u32 = 0,
    z: u32 = 0,
};

pub const TextureRegion = extern struct {
    texture: ?*Texture = null,
    mip_level: u32 = 0,
    layer: u32 = 0,
    x: u32 = 0,
    y: u32 = 0,
    z: u32 = 0,
    w: u32 = 0,
    h: u32 = 0,
    d: u32 = 1,
};

pub const BlitRegion = extern struct {
    texture: ?*Texture = null,
    mip_level: u32 = 0,
    layer_or_depth_plane: u32 = 0,
    x: u32 = 0,
    y: u32 = 0,
    w: u32 = 0,
    h: u32 = 0,
};

pub const BufferLocation = extern struct {
    buffer: ?*Buffer = null,
    offset: u32 = 0,
};

pub const BufferRegion = extern struct {
    buffer: ?*Buffer = null,
    offset: u32 = 0,
    size: u32 = 0,
};

pub const IndirectDrawCommand = extern struct {
    num_vertices: u32 = 0,
    num_instances: u32 = 0,
    first_vertex: u32 = 0,
    first_instance: u32 = 0,
};

pub const IndexedIndirectDrawCommand = extern struct {
    num_indices: u32 = 0,
    num_instances: u32 = 0,
    first_index: u32 = 0,
    vertex_offset: i32 = 0,
    first_instance: u32 = 0,
};

pub const IndirectDispatchCommand = extern struct {
    groupcount_x: u32 = 0,
    groupcount_y: u32 = 0,
    groupcount_z: u32 = 0,
};

pub const SamplerCreateInfo = extern struct {
    min_filter: Filter = .nearest,
    mag_filter: Filter = .nearest,
    mipmap_mode: SamplerMipmapMode = .nearest,
    address_mode_u: SamplerAddressMode = .repeat,
    address_mode_v: SamplerAddressMode = .repeat,
    address_mode_w: SamplerAddressMode = .repeat,
    mip_lod_bias: f32 = 0,
    max_anisotropy: f32 = 0,
    compare_op: CompareOp = .invalid,
    min_lod: f32 = 0,
    max_lod: f32 = 0,
    enable_anisotropy: bool = false,
    enable_compare: bool = false,
    padding1: u8 = 0,
    padding2: u8 = 0,
    props: u32 = 0,

    /// Bilinear filtering, clamped at the edges: the usual choice for a
    /// sprite or a UI texture.
    pub const linear_clamp: SamplerCreateInfo = .{
        .min_filter = .linear,
        .mag_filter = .linear,
        .mipmap_mode = .linear,
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
    };

    /// Point sampling, clamped: what pixel art wants.
    pub const nearest_clamp: SamplerCreateInfo = .{
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
    };
};

pub const VertexBufferDescription = extern struct {
    slot: u32 = 0,
    /// Bytes between one vertex and the next.
    pitch: u32 = 0,
    input_rate: VertexInputRate = .vertex,
    instance_step_rate: u32 = 0,
};

pub const VertexAttribute = extern struct {
    /// The shader's input location.
    location: u32 = 0,
    buffer_slot: u32 = 0,
    format: VertexElementFormat = .invalid,
    /// Byte offset within the vertex.
    offset: u32 = 0,
};

pub const VertexInputState = extern struct {
    vertex_buffer_descriptions: ?[*]const VertexBufferDescription = null,
    num_vertex_buffers: u32 = 0,
    vertex_attributes: ?[*]const VertexAttribute = null,
    num_vertex_attributes: u32 = 0,

    /// Builds the state from two slices, so the counts cannot drift from the
    /// arrays. Both must outlive the pipeline creation call.
    pub fn from(
        buffers: []const VertexBufferDescription,
        attributes: []const VertexAttribute,
    ) VertexInputState {
        return .{
            .vertex_buffer_descriptions = buffers.ptr,
            .num_vertex_buffers = @intCast(buffers.len),
            .vertex_attributes = attributes.ptr,
            .num_vertex_attributes = @intCast(attributes.len),
        };
    }
};

pub const StencilOpState = extern struct {
    fail_op: StencilOp = .invalid,
    pass_op: StencilOp = .invalid,
    depth_fail_op: StencilOp = .invalid,
    compare_op: CompareOp = .invalid,
};

pub const ColorTargetBlendState = extern struct {
    src_color_blendfactor: BlendFactor = .invalid,
    dst_color_blendfactor: BlendFactor = .invalid,
    color_blend_op: BlendOp = .invalid,
    src_alpha_blendfactor: BlendFactor = .invalid,
    dst_alpha_blendfactor: BlendFactor = .invalid,
    alpha_blend_op: BlendOp = .invalid,
    color_write_mask: ColorComponent = .{},
    enable_blend: bool = false,
    enable_color_write_mask: bool = false,
    padding1: u8 = 0,
    padding2: u8 = 0,

    /// Straight alpha blending.
    pub const alpha: ColorTargetBlendState = .{
        .src_color_blendfactor = .src_alpha,
        .dst_color_blendfactor = .one_minus_src_alpha,
        .color_blend_op = .add,
        .src_alpha_blendfactor = .one,
        .dst_alpha_blendfactor = .one_minus_src_alpha,
        .alpha_blend_op = .add,
        .enable_blend = true,
    };
};

pub const ShaderCreateInfo = extern struct {
    code_size: usize = 0,
    code: ?[*]const u8 = null,
    entrypoint: ?[*:0]const u8 = null,
    format: ShaderFormat = .{},
    stage: ShaderStage = .vertex,
    /// These four must match what the shader actually declares, or the
    /// backend will bind the wrong slots.
    num_samplers: u32 = 0,
    num_storage_textures: u32 = 0,
    num_storage_buffers: u32 = 0,
    num_uniform_buffers: u32 = 0,
    props: u32 = 0,
};

pub const TextureCreateInfo = extern struct {
    type: TextureType = .two_d,
    format: TextureFormat = .invalid,
    usage: TextureUsage = .{},
    width: u32 = 0,
    height: u32 = 0,
    /// Array layers for an array or cube texture, depth for a 3D one.
    layer_count_or_depth: u32 = 1,
    /// Mip levels. 1 means no mipmap chain.
    num_levels: u32 = 1,
    sample_count: SampleCount = .x1,
    props: u32 = 0,
};

pub const BufferCreateInfo = extern struct {
    usage: BufferUsage = .{},
    size: u32 = 0,
    props: u32 = 0,
};

pub const TransferBufferCreateInfo = extern struct {
    usage: TransferBufferUsage = .upload,
    size: u32 = 0,
    props: u32 = 0,
};

pub const RasterizerState = extern struct {
    fill_mode: FillMode = .fill,
    cull_mode: CullMode = .none,
    front_face: FrontFace = .counter_clockwise,
    depth_bias_constant_factor: f32 = 0,
    depth_bias_clamp: f32 = 0,
    depth_bias_slope_factor: f32 = 0,
    enable_depth_bias: bool = false,
    enable_depth_clip: bool = false,
    padding1: u8 = 0,
    padding2: u8 = 0,
};

pub const MultisampleState = extern struct {
    sample_count: SampleCount = .x1,
    sample_mask: u32 = 0,
    enable_mask: bool = false,
    enable_alpha_to_coverage: bool = false,
    padding2: u8 = 0,
    padding3: u8 = 0,
};

pub const DepthStencilState = extern struct {
    compare_op: CompareOp = .invalid,
    back_stencil_state: StencilOpState = .{},
    front_stencil_state: StencilOpState = .{},
    compare_mask: u8 = 0,
    write_mask: u8 = 0,
    enable_depth_test: bool = false,
    enable_depth_write: bool = false,
    enable_stencil_test: bool = false,
    padding1: u8 = 0,
    padding2: u8 = 0,
    padding3: u8 = 0,
};

pub const ColorTargetDescription = extern struct {
    format: TextureFormat = .invalid,
    blend_state: ColorTargetBlendState = .{},
};

pub const GraphicsPipelineTargetInfo = extern struct {
    color_target_descriptions: ?[*]const ColorTargetDescription = null,
    num_color_targets: u32 = 0,
    depth_stencil_format: TextureFormat = .invalid,
    has_depth_stencil_target: bool = false,
    padding1: u8 = 0,
    padding2: u8 = 0,
    padding3: u8 = 0,

    pub fn fromColorTargets(targets: []const ColorTargetDescription) GraphicsPipelineTargetInfo {
        return .{
            .color_target_descriptions = targets.ptr,
            .num_color_targets = @intCast(targets.len),
        };
    }
};

pub const GraphicsPipelineCreateInfo = extern struct {
    vertex_shader: ?*Shader = null,
    fragment_shader: ?*Shader = null,
    vertex_input_state: VertexInputState = .{},
    primitive_type: PrimitiveType = .triangle_list,
    rasterizer_state: RasterizerState = .{},
    multisample_state: MultisampleState = .{},
    depth_stencil_state: DepthStencilState = .{},
    target_info: GraphicsPipelineTargetInfo = .{},
    props: u32 = 0,
};

pub const ComputePipelineCreateInfo = extern struct {
    code_size: usize = 0,
    code: ?[*]const u8 = null,
    entrypoint: ?[*:0]const u8 = null,
    format: ShaderFormat = .{},
    num_samplers: u32 = 0,
    num_readonly_storage_textures: u32 = 0,
    num_readonly_storage_buffers: u32 = 0,
    num_readwrite_storage_textures: u32 = 0,
    num_readwrite_storage_buffers: u32 = 0,
    num_uniform_buffers: u32 = 0,
    /// The workgroup size the shader declares.
    threadcount_x: u32 = 1,
    threadcount_y: u32 = 1,
    threadcount_z: u32 = 1,
    props: u32 = 0,
};

pub const ColorTargetInfo = extern struct {
    texture: ?*Texture = null,
    mip_level: u32 = 0,
    layer_or_depth_plane: u32 = 0,
    clear_color: FColor = .{},
    load_op: LoadOp = .load,
    store_op: StoreOp = .store,
    resolve_texture: ?*Texture = null,
    resolve_mip_level: u32 = 0,
    resolve_layer: u32 = 0,
    /// Ask for a fresh copy of the texture rather than waiting for the last
    /// use of it to finish. The GPU API's answer to double buffering.
    cycle: bool = false,
    cycle_resolve_texture: bool = false,
    padding1: u8 = 0,
    padding2: u8 = 0,
};

pub const DepthStencilTargetInfo = extern struct {
    texture: ?*Texture = null,
    clear_depth: f32 = 0,
    load_op: LoadOp = .load,
    store_op: StoreOp = .store,
    stencil_load_op: LoadOp = .load,
    stencil_store_op: StoreOp = .store,
    cycle: bool = false,
    clear_stencil: u8 = 0,
    mip_level: u8 = 0,
    layer: u8 = 0,
};

pub const BlitInfo = extern struct {
    source: BlitRegion = .{},
    destination: BlitRegion = .{},
    load_op: LoadOp = .dont_care,
    clear_color: FColor = .{},
    flip_mode: pixels_mod.FlipMode = .none,
    filter: Filter = .nearest,
    cycle: bool = false,
    padding1: u8 = 0,
    padding2: u8 = 0,
    padding3: u8 = 0,
};

pub const BufferBinding = extern struct {
    buffer: ?*Buffer = null,
    offset: u32 = 0,
};

pub const TextureSamplerBinding = extern struct {
    texture: ?*Texture = null,
    sampler: ?*Sampler = null,
};

pub const StorageBufferReadWriteBinding = extern struct {
    buffer: ?*Buffer = null,
    cycle: bool = false,
    padding1: u8 = 0,
    padding2: u8 = 0,
    padding3: u8 = 0,
};

pub const StorageTextureReadWriteBinding = extern struct {
    texture: ?*Texture = null,
    mip_level: u32 = 0,
    layer: u32 = 0,
    cycle: bool = false,
    padding1: u8 = 0,
    padding2: u8 = 0,
    padding3: u8 = 0,
};

// ---------------------------------------------------------------------
// Drivers
// ---------------------------------------------------------------------

pub fn driverCount() usize {
    const count = raw.SDL_GetNumGPUDrivers();
    return if (count < 0) 0 else @intCast(count);
}

/// "vulkan", "metal", "direct3d12". Owned by SDL.
pub fn driverName(index: usize) ?[]const u8 {
    const text = raw.SDL_GetGPUDriver(@intCast(index));
    if (text == null) return null;
    return std.mem.span(text);
}

/// Whether a device could be made for these shader formats, without making
/// one. `driver` null asks about any backend.
pub fn supportsShaderFormats(formats: ShaderFormat, driver: ?[:0]const u8) bool {
    return raw.SDL_GPUSupportsShaderFormats(
        @bitCast(formats),
        if (driver) |d| d.ptr else null,
    );
}

/// The texture format that holds the same pixels as an SDL surface format.
pub fn textureFormatFromPixelFormat(format: pixels_mod.PixelFormat) TextureFormat {
    return @fromBackingInt(@intCast(raw.SDL_GetGPUTextureFormatFromPixelFormat(@backingInt(format))));
}

/// What `CommandBuffer.acquireSwapchainTexture` gives back.
pub const SwapchainTexture = struct {
    /// Null when the swapchain has no image right now: the window is
    /// minimised, or every frame slot is still in flight. That is not an
    /// error -- skip the frame's drawing and submit the command buffer
    /// anyway.
    ///
    /// Owned by the swapchain. Never release it, and never touch it once the
    /// command buffer has been submitted.
    texture: ?*Texture,
    width: u32,
    height: u32,
};

// ---------------------------------------------------------------------
// Device
// ---------------------------------------------------------------------

pub const Device = opaque {
    /// Creates a device for the shader formats you can supply.
    ///
    /// `debug_mode` turns on the backend's validation layers, which is where
    /// the real error messages come from -- keep it on outside release
    /// builds. `driver` null lets SDL choose.
    pub fn init(formats: ShaderFormat, debug_mode: bool, backend: ?[:0]const u8) Error!*Device {
        const handle = raw.SDL_CreateGPUDevice(
            @bitCast(formats),
            debug_mode,
            if (backend) |name| name.ptr else null,
        );
        return @ptrCast(try errors.checkPtr(handle));
    }

    pub fn initWithProperties(props: Properties) Error!*Device {
        return @ptrCast(try errors.checkPtr(raw.SDL_CreateGPUDeviceWithProperties(props.id)));
    }

    /// Destroys the device and everything still attached to it.
    pub fn deinit(self: *Device) void {
        raw.SDL_DestroyGPUDevice(@ptrCast(self));
    }

    /// Owned by SDL.
    pub fn driver(self: *Device) []const u8 {
        const text = raw.SDL_GetGPUDeviceDriver(@ptrCast(self));
        if (text == null) return "";
        return std.mem.span(text);
    }

    /// Which of the formats asked for the device actually took.
    pub fn shaderFormats(self: *Device) ShaderFormat {
        return @bitCast(raw.SDL_GetGPUShaderFormats(@ptrCast(self)));
    }

    pub fn properties(self: *Device) Properties {
        return .{ .id = raw.SDL_GetGPUDeviceProperties(@ptrCast(self)) };
    }

    // -- swapchain ------------------------------------------------------

    /// Attaches a window, creating its swapchain. Nothing can be presented
    /// until this succeeds.
    pub fn claimWindow(self: *Device, window: Window) Error!void {
        try check(raw.SDL_ClaimWindowForGPUDevice(@ptrCast(self), window.handle));
    }

    /// Do this before destroying the window, or the swapchain outlives what
    /// it points at.
    pub fn releaseWindow(self: *Device, window: Window) void {
        raw.SDL_ReleaseWindowFromGPUDevice(@ptrCast(self), window.handle);
    }

    pub fn setSwapchainParameters(
        self: *Device,
        window: Window,
        composition: SwapchainComposition,
        present_mode: PresentMode,
    ) Error!void {
        try check(raw.SDL_SetGPUSwapchainParameters(
            @ptrCast(self),
            window.handle,
            @backingInt(composition),
            @backingInt(present_mode),
        ));
    }

    /// Only `.vsync` is guaranteed; ask before setting either of the others.
    pub fn supportsPresentMode(self: *Device, window: Window, mode: PresentMode) bool {
        return raw.SDL_WindowSupportsGPUPresentMode(
            @ptrCast(self),
            window.handle,
            @backingInt(mode),
        );
    }

    pub fn supportsSwapchainComposition(
        self: *Device,
        window: Window,
        composition: SwapchainComposition,
    ) bool {
        return raw.SDL_WindowSupportsGPUSwapchainComposition(
            @ptrCast(self),
            window.handle,
            @backingInt(composition),
        );
    }

    /// The format a pipeline drawing to this window's swapchain must target.
    pub fn swapchainTextureFormat(self: *Device, window: Window) TextureFormat {
        return @fromBackingInt(@intCast(raw.SDL_GetGPUSwapchainTextureFormat(@ptrCast(self), window.handle)));
    }

    /// How many frames may be in flight, 1 to 3. Fewer means lower latency
    /// and more waiting; more means the opposite.
    pub fn setAllowedFramesInFlight(self: *Device, count: u32) Error!void {
        try check(raw.SDL_SetGPUAllowedFramesInFlight(@ptrCast(self), count));
    }

    /// Blocks until the swapchain has an image free, so the acquire that
    /// follows cannot come back empty.
    pub fn waitForSwapchain(self: *Device, window: Window) Error!void {
        try check(raw.SDL_WaitForGPUSwapchain(@ptrCast(self), window.handle));
    }

    // -- command buffers ------------------------------------------------

    /// The command buffer belongs to the thread that acquired it, and must be
    /// submitted or cancelled from that thread.
    pub fn acquireCommandBuffer(self: *Device) Error!*CommandBuffer {
        return @ptrCast(try errors.checkPtr(raw.SDL_AcquireGPUCommandBuffer(@ptrCast(self))));
    }

    // -- resources ------------------------------------------------------

    pub fn createBuffer(self: *Device, info: BufferCreateInfo) Error!*Buffer {
        const handle = raw.SDL_CreateGPUBuffer(@ptrCast(self), @ptrCast(&info));
        return @ptrCast(try errors.checkPtr(handle));
    }

    pub fn createTransferBuffer(
        self: *Device,
        info: TransferBufferCreateInfo,
    ) Error!*TransferBuffer {
        const handle = raw.SDL_CreateGPUTransferBuffer(@ptrCast(self), @ptrCast(&info));
        return @ptrCast(try errors.checkPtr(handle));
    }

    pub fn createTexture(self: *Device, info: TextureCreateInfo) Error!*Texture {
        const handle = raw.SDL_CreateGPUTexture(@ptrCast(self), @ptrCast(&info));
        return @ptrCast(try errors.checkPtr(handle));
    }

    pub fn createSampler(self: *Device, info: SamplerCreateInfo) Error!*Sampler {
        const handle = raw.SDL_CreateGPUSampler(@ptrCast(self), @ptrCast(&info));
        return @ptrCast(try errors.checkPtr(handle));
    }

    /// `info.code` is backend-specific bytecode -- see this module's header.
    pub fn createShader(self: *Device, info: ShaderCreateInfo) Error!*Shader {
        const handle = raw.SDL_CreateGPUShader(@ptrCast(self), @ptrCast(&info));
        return @ptrCast(try errors.checkPtr(handle));
    }

    /// The shaders can be released as soon as this returns: the pipeline
    /// keeps what it needs.
    pub fn createGraphicsPipeline(
        self: *Device,
        info: GraphicsPipelineCreateInfo,
    ) Error!*GraphicsPipeline {
        const handle = raw.SDL_CreateGPUGraphicsPipeline(@ptrCast(self), @ptrCast(&info));
        return @ptrCast(try errors.checkPtr(handle));
    }

    pub fn createComputePipeline(
        self: *Device,
        info: ComputePipelineCreateInfo,
    ) Error!*ComputePipeline {
        const handle = raw.SDL_CreateGPUComputePipeline(@ptrCast(self), @ptrCast(&info));
        return @ptrCast(try errors.checkPtr(handle));
    }

    // Releases are deferred until the GPU is finished with the resource, so
    // they are safe to call while work is still in flight -- but not while a
    // command buffer that still references the resource is unsubmitted.

    pub fn releaseBuffer(self: *Device, buffer: *Buffer) void {
        raw.SDL_ReleaseGPUBuffer(@ptrCast(self), @ptrCast(buffer));
    }

    pub fn releaseTransferBuffer(self: *Device, buffer: *TransferBuffer) void {
        raw.SDL_ReleaseGPUTransferBuffer(@ptrCast(self), @ptrCast(buffer));
    }

    pub fn releaseTexture(self: *Device, texture: *Texture) void {
        raw.SDL_ReleaseGPUTexture(@ptrCast(self), @ptrCast(texture));
    }

    pub fn releaseSampler(self: *Device, sampler: *Sampler) void {
        raw.SDL_ReleaseGPUSampler(@ptrCast(self), @ptrCast(sampler));
    }

    pub fn releaseShader(self: *Device, shader: *Shader) void {
        raw.SDL_ReleaseGPUShader(@ptrCast(self), @ptrCast(shader));
    }

    pub fn releaseGraphicsPipeline(self: *Device, pipeline: *GraphicsPipeline) void {
        raw.SDL_ReleaseGPUGraphicsPipeline(@ptrCast(self), @ptrCast(pipeline));
    }

    pub fn releaseComputePipeline(self: *Device, pipeline: *ComputePipeline) void {
        raw.SDL_ReleaseGPUComputePipeline(@ptrCast(self), @ptrCast(pipeline));
    }

    /// Shows up in a graphics debugger's capture. Debug builds only.
    pub fn setBufferName(self: *Device, buffer: *Buffer, name: [:0]const u8) void {
        raw.SDL_SetGPUBufferName(@ptrCast(self), @ptrCast(buffer), name.ptr);
    }

    pub fn setTextureName(self: *Device, texture: *Texture, name: [:0]const u8) void {
        raw.SDL_SetGPUTextureName(@ptrCast(self), @ptrCast(texture), name.ptr);
    }

    // -- transfer memory ------------------------------------------------

    /// CPU-visible memory for a transfer buffer. `size` is the size the
    /// buffer was created with -- SDL does not report it back, and a slice
    /// longer than the allocation is a buffer overrun.
    ///
    /// `cycle` asks for fresh memory rather than waiting for the last use to
    /// finish, which is what a per-frame staging buffer wants.
    pub fn mapTransferBuffer(
        self: *Device,
        buffer: *TransferBuffer,
        size: usize,
        cycle: bool,
    ) Error![]u8 {
        const data = raw.SDL_MapGPUTransferBuffer(@ptrCast(self), @ptrCast(buffer), cycle);
        const bytes: [*]u8 = @ptrCast(try errors.checkPtr(data));
        return bytes[0..size];
    }

    pub fn unmapTransferBuffer(self: *Device, buffer: *TransferBuffer) void {
        raw.SDL_UnmapGPUTransferBuffer(@ptrCast(self), @ptrCast(buffer));
    }

    // -- synchronisation ------------------------------------------------

    /// Blocks until every submitted command buffer has finished. The blunt
    /// instrument: right before teardown, wrong inside a frame.
    pub fn waitForIdle(self: *Device) Error!void {
        try check(raw.SDL_WaitForGPUIdle(@ptrCast(self)));
    }

    /// `wait_all` false returns as soon as any one fence is signalled.
    pub fn waitForFences(self: *Device, wait_all: bool, fences: []const *Fence) Error!void {
        try check(raw.SDL_WaitForGPUFences(
            @ptrCast(self),
            wait_all,
            @ptrCast(fences.ptr),
            @intCast(fences.len),
        ));
    }

    /// True when the work the fence was taken for has finished. Does not
    /// block.
    pub fn queryFence(self: *Device, fence: *Fence) bool {
        return raw.SDL_QueryGPUFence(@ptrCast(self), @ptrCast(fence));
    }

    /// Every fence from `submitAndAcquireFence` must be released.
    pub fn releaseFence(self: *Device, fence: *Fence) void {
        raw.SDL_ReleaseGPUFence(@ptrCast(self), @ptrCast(fence));
    }

    // -- capabilities ---------------------------------------------------

    pub fn supportsTextureFormat(
        self: *Device,
        format: TextureFormat,
        texture_type: TextureType,
        usage: TextureUsage,
    ) bool {
        return raw.SDL_GPUTextureSupportsFormat(
            @ptrCast(self),
            @backingInt(format),
            @backingInt(texture_type),
            @bitCast(usage),
        );
    }

    pub fn supportsSampleCount(
        self: *Device,
        format: TextureFormat,
        count: SampleCount,
    ) bool {
        return raw.SDL_GPUTextureSupportsSampleCount(
            @ptrCast(self),
            @backingInt(format),
            @backingInt(count),
        );
    }
};

// ---------------------------------------------------------------------
// Resources
// ---------------------------------------------------------------------
//
// These are handles the device hands out and the device takes back: their
// verbs live on `Device`, so the bodies here are empty on purpose.

pub const Buffer = opaque {};
pub const TransferBuffer = opaque {};
pub const Texture = opaque {};
pub const Sampler = opaque {};
pub const Shader = opaque {};
pub const GraphicsPipeline = opaque {};
pub const ComputePipeline = opaque {};
pub const Fence = opaque {};

// ---------------------------------------------------------------------
// Command buffers
// ---------------------------------------------------------------------

pub const CommandBuffer = opaque {
    /// Takes the next swapchain image, without blocking. `texture` null means
    /// none was free -- see `SwapchainTexture`.
    pub fn acquireSwapchainTexture(self: *CommandBuffer, window: Window) Error!SwapchainTexture {
        var texture: ?*raw.SDL_GPUTexture = null;
        var width: u32 = 0;
        var height: u32 = 0;
        try check(raw.SDL_AcquireGPUSwapchainTexture(
            @ptrCast(self),
            window.handle,
            &texture,
            &width,
            &height,
        ));
        return .{ .texture = @ptrCast(texture), .width = width, .height = height };
    }

    /// Blocks until an image is free, then takes it. Costs latency and gains
    /// a frame that is never skipped -- the right default for a simple loop.
    pub fn waitAndAcquireSwapchainTexture(
        self: *CommandBuffer,
        window: Window,
    ) Error!SwapchainTexture {
        var texture: ?*raw.SDL_GPUTexture = null;
        var width: u32 = 0;
        var height: u32 = 0;
        try check(raw.SDL_WaitAndAcquireGPUSwapchainTexture(
            @ptrCast(self),
            window.handle,
            &texture,
            &width,
            &height,
        ));
        return .{ .texture = @ptrCast(texture), .width = width, .height = height };
    }

    /// `depth_stencil` null draws without a depth buffer. End the pass before
    /// beginning another on the same command buffer.
    pub fn beginRenderPass(
        self: *CommandBuffer,
        color_targets: []const ColorTargetInfo,
        depth_stencil: ?*const DepthStencilTargetInfo,
    ) Error!*RenderPass {
        const handle = raw.SDL_BeginGPURenderPass(
            @ptrCast(self),
            @ptrCast(color_targets.ptr),
            @intCast(color_targets.len),
            @ptrCast(depth_stencil),
        );
        return @ptrCast(try errors.checkPtr(handle));
    }

    pub fn beginComputePass(
        self: *CommandBuffer,
        storage_textures: []const StorageTextureReadWriteBinding,
        storage_buffers: []const StorageBufferReadWriteBinding,
    ) Error!*ComputePass {
        const handle = raw.SDL_BeginGPUComputePass(
            @ptrCast(self),
            @ptrCast(storage_textures.ptr),
            @intCast(storage_textures.len),
            @ptrCast(storage_buffers.ptr),
            @intCast(storage_buffers.len),
        );
        return @ptrCast(try errors.checkPtr(handle));
    }

    pub fn beginCopyPass(self: *CommandBuffer) Error!*CopyPass {
        return @ptrCast(try errors.checkPtr(raw.SDL_BeginGPUCopyPass(@ptrCast(self))));
    }

    // -- uniforms -------------------------------------------------------
    //
    // Uniform data is pushed onto the command buffer, not bound as a
    // resource, and it applies to every draw after the push. `slot` is the
    // shader's uniform buffer index.

    pub fn pushVertexUniformBytes(self: *CommandBuffer, slot: u32, data: []const u8) void {
        raw.SDL_PushGPUVertexUniformData(@ptrCast(self), slot, data.ptr, @intCast(data.len));
    }

    pub fn pushFragmentUniformBytes(self: *CommandBuffer, slot: u32, data: []const u8) void {
        raw.SDL_PushGPUFragmentUniformData(@ptrCast(self), slot, data.ptr, @intCast(data.len));
    }

    pub fn pushComputeUniformBytes(self: *CommandBuffer, slot: u32, data: []const u8) void {
        raw.SDL_PushGPUComputeUniformData(@ptrCast(self), slot, data.ptr, @intCast(data.len));
    }

    /// Pushes one value, sized by its type. `value` must be an `extern` or
    /// `packed` struct whose layout matches the shader's.
    pub fn pushVertexUniform(self: *CommandBuffer, slot: u32, value: anytype) void {
        self.pushVertexUniformBytes(slot, std.mem.asBytes(&value));
    }

    pub fn pushFragmentUniform(self: *CommandBuffer, slot: u32, value: anytype) void {
        self.pushFragmentUniformBytes(slot, std.mem.asBytes(&value));
    }

    pub fn pushComputeUniform(self: *CommandBuffer, slot: u32, value: anytype) void {
        self.pushComputeUniformBytes(slot, std.mem.asBytes(&value));
    }

    // -- outside a pass -------------------------------------------------

    /// Copies between textures with scaling and format conversion. Not part
    /// of any pass.
    pub fn blitTexture(self: *CommandBuffer, info: BlitInfo) void {
        raw.SDL_BlitGPUTexture(@ptrCast(self), @ptrCast(&info));
    }

    /// Fills every mip level below level 0. The texture needs more than one
    /// level and both `sampler` and `color_target` usage.
    pub fn generateMipmaps(self: *CommandBuffer, texture: *Texture) void {
        raw.SDL_GenerateMipmapsForGPUTexture(@ptrCast(self), @ptrCast(texture));
    }

    pub fn insertDebugLabel(self: *CommandBuffer, text: [:0]const u8) void {
        raw.SDL_InsertGPUDebugLabel(@ptrCast(self), text.ptr);
    }

    /// Opens a named region in a graphics debugger's capture. Pair with
    /// `popDebugGroup`.
    pub fn pushDebugGroup(self: *CommandBuffer, name: [:0]const u8) void {
        raw.SDL_PushGPUDebugGroup(@ptrCast(self), name.ptr);
    }

    pub fn popDebugGroup(self: *CommandBuffer) void {
        raw.SDL_PopGPUDebugGroup(@ptrCast(self));
    }

    // -- finishing ------------------------------------------------------

    /// Hands the work to the GPU. The command buffer is invalid afterwards,
    /// and so is any swapchain texture acquired from it.
    pub fn submit(self: *CommandBuffer) Error!void {
        try check(raw.SDL_SubmitGPUCommandBuffer(@ptrCast(self)));
    }

    /// The same, with a fence to wait on. Every fence must be released with
    /// `Device.releaseFence`.
    pub fn submitAndAcquireFence(self: *CommandBuffer) Error!*Fence {
        const handle = raw.SDL_SubmitGPUCommandBufferAndAcquireFence(@ptrCast(self));
        return @ptrCast(try errors.checkPtr(handle));
    }

    /// Throws the work away. Only valid on a command buffer whose swapchain
    /// texture was never acquired.
    pub fn cancel(self: *CommandBuffer) Error!void {
        try check(raw.SDL_CancelGPUCommandBuffer(@ptrCast(self)));
    }
};

// ---------------------------------------------------------------------
// Passes
// ---------------------------------------------------------------------

pub const RenderPass = opaque {
    pub fn bindGraphicsPipeline(self: *RenderPass, pipeline: *GraphicsPipeline) void {
        raw.SDL_BindGPUGraphicsPipeline(@ptrCast(self), @ptrCast(pipeline));
    }

    pub fn setViewport(self: *RenderPass, viewport: Viewport) void {
        raw.SDL_SetGPUViewport(@ptrCast(self), @ptrCast(&viewport));
    }

    pub fn setScissor(self: *RenderPass, area: Rect) void {
        raw.SDL_SetGPUScissor(@ptrCast(self), @ptrCast(&area));
    }

    /// The colour the `constant_color` blend factors refer to.
    pub fn setBlendConstants(self: *RenderPass, color: FColor) void {
        raw.SDL_SetGPUBlendConstants(@ptrCast(self), @bitCast(color));
    }

    pub fn setStencilReference(self: *RenderPass, reference: u8) void {
        raw.SDL_SetGPUStencilReference(@ptrCast(self), reference);
    }

    pub fn bindVertexBuffers(
        self: *RenderPass,
        first_slot: u32,
        bindings: []const BufferBinding,
    ) void {
        raw.SDL_BindGPUVertexBuffers(
            @ptrCast(self),
            first_slot,
            @ptrCast(bindings.ptr),
            @intCast(bindings.len),
        );
    }

    pub fn bindIndexBuffer(
        self: *RenderPass,
        binding: BufferBinding,
        element_size: IndexElementSize,
    ) void {
        raw.SDL_BindGPUIndexBuffer(@ptrCast(self), @ptrCast(&binding), @backingInt(element_size));
    }

    pub fn bindVertexSamplers(
        self: *RenderPass,
        first_slot: u32,
        bindings: []const TextureSamplerBinding,
    ) void {
        raw.SDL_BindGPUVertexSamplers(
            @ptrCast(self),
            first_slot,
            @ptrCast(bindings.ptr),
            @intCast(bindings.len),
        );
    }

    pub fn bindFragmentSamplers(
        self: *RenderPass,
        first_slot: u32,
        bindings: []const TextureSamplerBinding,
    ) void {
        raw.SDL_BindGPUFragmentSamplers(
            @ptrCast(self),
            first_slot,
            @ptrCast(bindings.ptr),
            @intCast(bindings.len),
        );
    }

    pub fn bindVertexStorageTextures(
        self: *RenderPass,
        first_slot: u32,
        textures: []const *Texture,
    ) void {
        raw.SDL_BindGPUVertexStorageTextures(
            @ptrCast(self),
            first_slot,
            @ptrCast(textures.ptr),
            @intCast(textures.len),
        );
    }

    pub fn bindVertexStorageBuffers(
        self: *RenderPass,
        first_slot: u32,
        buffers: []const *Buffer,
    ) void {
        raw.SDL_BindGPUVertexStorageBuffers(
            @ptrCast(self),
            first_slot,
            @ptrCast(buffers.ptr),
            @intCast(buffers.len),
        );
    }

    pub fn bindFragmentStorageTextures(
        self: *RenderPass,
        first_slot: u32,
        textures: []const *Texture,
    ) void {
        raw.SDL_BindGPUFragmentStorageTextures(
            @ptrCast(self),
            first_slot,
            @ptrCast(textures.ptr),
            @intCast(textures.len),
        );
    }

    pub fn bindFragmentStorageBuffers(
        self: *RenderPass,
        first_slot: u32,
        buffers: []const *Buffer,
    ) void {
        raw.SDL_BindGPUFragmentStorageBuffers(
            @ptrCast(self),
            first_slot,
            @ptrCast(buffers.ptr),
            @intCast(buffers.len),
        );
    }

    pub fn drawPrimitives(
        self: *RenderPass,
        num_vertices: u32,
        num_instances: u32,
        first_vertex: u32,
        first_instance: u32,
    ) void {
        raw.SDL_DrawGPUPrimitives(
            @ptrCast(self),
            num_vertices,
            num_instances,
            first_vertex,
            first_instance,
        );
    }

    pub fn drawIndexedPrimitives(
        self: *RenderPass,
        num_indices: u32,
        num_instances: u32,
        first_index: u32,
        vertex_offset: i32,
        first_instance: u32,
    ) void {
        raw.SDL_DrawGPUIndexedPrimitives(
            @ptrCast(self),
            num_indices,
            num_instances,
            first_index,
            vertex_offset,
            first_instance,
        );
    }

    /// Reads the draw arguments from a buffer the GPU wrote. `buffer` holds
    /// `draw_count` `IndirectDrawCommand`s starting at `offset`.
    pub fn drawPrimitivesIndirect(
        self: *RenderPass,
        buffer: *Buffer,
        offset: u32,
        draw_count: u32,
    ) void {
        raw.SDL_DrawGPUPrimitivesIndirect(@ptrCast(self), @ptrCast(buffer), offset, draw_count);
    }

    pub fn drawIndexedPrimitivesIndirect(
        self: *RenderPass,
        buffer: *Buffer,
        offset: u32,
        draw_count: u32,
    ) void {
        raw.SDL_DrawGPUIndexedPrimitivesIndirect(
            @ptrCast(self),
            @ptrCast(buffer),
            offset,
            draw_count,
        );
    }

    /// Ends the pass. The handle is invalid afterwards.
    pub fn end(self: *RenderPass) void {
        raw.SDL_EndGPURenderPass(@ptrCast(self));
    }
};

pub const ComputePass = opaque {
    pub fn bindComputePipeline(self: *ComputePass, pipeline: *ComputePipeline) void {
        raw.SDL_BindGPUComputePipeline(@ptrCast(self), @ptrCast(pipeline));
    }

    pub fn bindSamplers(
        self: *ComputePass,
        first_slot: u32,
        bindings: []const TextureSamplerBinding,
    ) void {
        raw.SDL_BindGPUComputeSamplers(
            @ptrCast(self),
            first_slot,
            @ptrCast(bindings.ptr),
            @intCast(bindings.len),
        );
    }

    /// The read-only storage textures. The read-write ones were bound when
    /// the pass began.
    pub fn bindStorageTextures(
        self: *ComputePass,
        first_slot: u32,
        textures: []const *Texture,
    ) void {
        raw.SDL_BindGPUComputeStorageTextures(
            @ptrCast(self),
            first_slot,
            @ptrCast(textures.ptr),
            @intCast(textures.len),
        );
    }

    pub fn bindStorageBuffers(
        self: *ComputePass,
        first_slot: u32,
        buffers: []const *Buffer,
    ) void {
        raw.SDL_BindGPUComputeStorageBuffers(
            @ptrCast(self),
            first_slot,
            @ptrCast(buffers.ptr),
            @intCast(buffers.len),
        );
    }

    /// Counts are workgroups, not threads: multiply by the pipeline's
    /// `threadcount_*` for the number of invocations.
    pub fn dispatch(self: *ComputePass, groups_x: u32, groups_y: u32, groups_z: u32) void {
        raw.SDL_DispatchGPUCompute(@ptrCast(self), groups_x, groups_y, groups_z);
    }

    pub fn dispatchIndirect(self: *ComputePass, buffer: *Buffer, offset: u32) void {
        raw.SDL_DispatchGPUComputeIndirect(@ptrCast(self), @ptrCast(buffer), offset);
    }

    pub fn end(self: *ComputePass) void {
        raw.SDL_EndGPUComputePass(@ptrCast(self));
    }
};

pub const CopyPass = opaque {
    /// `cycle` asks for a fresh copy of the destination rather than waiting
    /// for its last use to finish.
    pub fn uploadToBuffer(
        self: *CopyPass,
        source: TransferBufferLocation,
        destination: BufferRegion,
        cycle: bool,
    ) void {
        raw.SDL_UploadToGPUBuffer(@ptrCast(self), @ptrCast(&source), @ptrCast(&destination), cycle);
    }

    pub fn uploadToTexture(
        self: *CopyPass,
        source: TextureTransferInfo,
        destination: TextureRegion,
        cycle: bool,
    ) void {
        raw.SDL_UploadToGPUTexture(@ptrCast(self), @ptrCast(&source), @ptrCast(&destination), cycle);
    }

    /// The data is not in the transfer buffer until the command buffer has
    /// been submitted *and* its fence has signalled.
    pub fn downloadFromBuffer(
        self: *CopyPass,
        source: BufferRegion,
        destination: TransferBufferLocation,
    ) void {
        raw.SDL_DownloadFromGPUBuffer(@ptrCast(self), @ptrCast(&source), @ptrCast(&destination));
    }

    pub fn downloadFromTexture(
        self: *CopyPass,
        source: TextureRegion,
        destination: TextureTransferInfo,
    ) void {
        raw.SDL_DownloadFromGPUTexture(@ptrCast(self), @ptrCast(&source), @ptrCast(&destination));
    }

    pub fn copyBufferToBuffer(
        self: *CopyPass,
        source: BufferLocation,
        destination: BufferLocation,
        size: u32,
        cycle: bool,
    ) void {
        raw.SDL_CopyGPUBufferToBuffer(
            @ptrCast(self),
            @ptrCast(&source),
            @ptrCast(&destination),
            size,
            cycle,
        );
    }

    pub fn copyTextureToTexture(
        self: *CopyPass,
        source: TextureLocation,
        destination: TextureLocation,
        w: u32,
        h: u32,
        d: u32,
        cycle: bool,
    ) void {
        raw.SDL_CopyGPUTextureToTexture(
            @ptrCast(self),
            @ptrCast(&source),
            @ptrCast(&destination),
            w,
            h,
            d,
            cycle,
        );
    }

    pub fn end(self: *CopyPass) void {
        raw.SDL_EndGPUCopyPass(@ptrCast(self));
    }
};

comptime {
    // Every struct above is handed to SDL by pointer, so a layout mismatch
    // would be a silent memory bug rather than a compile error.
    const pairs = .{
        .{ Viewport, raw.SDL_GPUViewport },
        .{ TextureTransferInfo, raw.SDL_GPUTextureTransferInfo },
        .{ TransferBufferLocation, raw.SDL_GPUTransferBufferLocation },
        .{ TextureLocation, raw.SDL_GPUTextureLocation },
        .{ TextureRegion, raw.SDL_GPUTextureRegion },
        .{ BlitRegion, raw.SDL_GPUBlitRegion },
        .{ BufferLocation, raw.SDL_GPUBufferLocation },
        .{ BufferRegion, raw.SDL_GPUBufferRegion },
        .{ IndirectDrawCommand, raw.SDL_GPUIndirectDrawCommand },
        .{ IndexedIndirectDrawCommand, raw.SDL_GPUIndexedIndirectDrawCommand },
        .{ IndirectDispatchCommand, raw.SDL_GPUIndirectDispatchCommand },
        .{ SamplerCreateInfo, raw.SDL_GPUSamplerCreateInfo },
        .{ VertexBufferDescription, raw.SDL_GPUVertexBufferDescription },
        .{ VertexAttribute, raw.SDL_GPUVertexAttribute },
        .{ VertexInputState, raw.SDL_GPUVertexInputState },
        .{ StencilOpState, raw.SDL_GPUStencilOpState },
        .{ ColorTargetBlendState, raw.SDL_GPUColorTargetBlendState },
        .{ ShaderCreateInfo, raw.SDL_GPUShaderCreateInfo },
        .{ TextureCreateInfo, raw.SDL_GPUTextureCreateInfo },
        .{ BufferCreateInfo, raw.SDL_GPUBufferCreateInfo },
        .{ TransferBufferCreateInfo, raw.SDL_GPUTransferBufferCreateInfo },
        .{ RasterizerState, raw.SDL_GPURasterizerState },
        .{ MultisampleState, raw.SDL_GPUMultisampleState },
        .{ DepthStencilState, raw.SDL_GPUDepthStencilState },
        .{ ColorTargetDescription, raw.SDL_GPUColorTargetDescription },
        .{ GraphicsPipelineTargetInfo, raw.SDL_GPUGraphicsPipelineTargetInfo },
        .{ GraphicsPipelineCreateInfo, raw.SDL_GPUGraphicsPipelineCreateInfo },
        .{ ComputePipelineCreateInfo, raw.SDL_GPUComputePipelineCreateInfo },
        .{ ColorTargetInfo, raw.SDL_GPUColorTargetInfo },
        .{ DepthStencilTargetInfo, raw.SDL_GPUDepthStencilTargetInfo },
        .{ BlitInfo, raw.SDL_GPUBlitInfo },
        .{ BufferBinding, raw.SDL_GPUBufferBinding },
        .{ TextureSamplerBinding, raw.SDL_GPUTextureSamplerBinding },
        .{ StorageBufferReadWriteBinding, raw.SDL_GPUStorageBufferReadWriteBinding },
        .{ StorageTextureReadWriteBinding, raw.SDL_GPUStorageTextureReadWriteBinding },
    };
    for (pairs) |pair| {
        std.debug.assert(@sizeOf(pair[0]) == @sizeOf(pair[1]));
        std.debug.assert(@alignOf(pair[0]) == @alignOf(pair[1]));
    }
}
